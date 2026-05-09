package v1

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	admissionv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"

	"container-security-mts/internal/cosign"
	"container-security-mts/internal/notifications"
	"container-security-mts/internal/opa"
	"container-security-mts/internal/scanner"
	"container-security-mts/pkg/utils"
)

const (
	contentTypeHeader = "Content-Type"
	contentTypeJSON   = "application/json"
)

// WebhookError represents categorized webhook errors
type WebhookError struct {
	Category string
	Code     string
	Message  string
	Cause    error
}

func (we *WebhookError) Error() string {
	if we.Cause != nil {
		return fmt.Sprintf("[%s] %s: %v", we.Category, we.Message, we.Cause)
	}
	return fmt.Sprintf("[%s] %s", we.Category, we.Message)
}

// Error categories
const (
	ErrorCategoryValidation = "VALIDATION"
	ErrorCategoryProcessing = "PROCESSING"
	ErrorCategorySecurity   = "SECURITY"
	ErrorCategoryInternal   = "INTERNAL"
)

// WebhookHandler handles Kubernetes admission webhook requests
type WebhookHandler struct {
	trivyScanner   *scanner.TrivyScanner
	cosignVerifier *cosign.CosignVerifier
	opaEvaluator   *opa.OPAEvaluator
	logger         *utils.Logger
	config         *WebhookConfig
	decoder        runtime.Decoder
	metrics        *utils.Metrics
	notifier       notifications.Notifier
}

// NewWebhookHandler creates a new webhook handler
func NewWebhookHandler(trivyScanner *scanner.TrivyScanner, cosignVerifier *cosign.CosignVerifier, opaEvaluator *opa.OPAEvaluator, logger *utils.Logger, config *WebhookConfig, metrics *utils.Metrics, notifier notifications.Notifier) *WebhookHandler {
	scheme := runtime.NewScheme()
	admissionv1.AddToScheme(scheme)
	corev1.AddToScheme(scheme)

	return &WebhookHandler{
		trivyScanner:   trivyScanner,
		cosignVerifier: cosignVerifier,
		opaEvaluator:   opaEvaluator,
		logger:         logger,
		config:         config,
		decoder:        serializer.NewCodecFactory(scheme).UniversalDeserializer(),
		metrics:        metrics,
		notifier:       notifier,
	}
}

// HandleAdmission processes admission webhook requests
func (wh *WebhookHandler) HandleAdmission(w http.ResponseWriter, r *http.Request) {
	startTime := time.Now()
	requestID := fmt.Sprintf("%d", startTime.UnixNano())

	wh.logger.Infof("[REQUEST %s] Received admission request from %s", requestID, r.RemoteAddr)

	// Validate request
	if err := wh.validateAdmissionRequest(r); err != nil {
		wh.handleWebhookError(w, err, requestID)
		return
	}

	// Read and validate request body
	body, err := io.ReadAll(io.LimitReader(r.Body, wh.config.MaxRequestSize))
	if err != nil {
		wh.logger.Errorf("[REQUEST %s] Failed to read request body: %v", requestID, err)
		wh.sendErrorResponse(w, "READ_ERROR", "Failed to read request body", http.StatusBadRequest, requestID)
		return
	}

	if len(body) == 0 {
		wh.sendErrorResponse(w, "EMPTY_BODY", "Request body cannot be empty", http.StatusBadRequest, requestID)
		return
	}

	// Parse admission review request
	var admissionReview admissionv1.AdmissionReview
	if _, _, err := wh.decoder.Decode(body, nil, &admissionReview); err != nil {
		wh.logger.Errorf("[REQUEST %s] Failed to decode admission review: %v", requestID, err)
		wh.sendErrorResponse(w, "DECODE_ERROR", "Failed to decode admission review", http.StatusBadRequest, requestID)
		return
	}

	if admissionReview.Request == nil {
		wh.sendErrorResponse(w, "INVALID_REQUEST", "Admission request is nil", http.StatusBadRequest, requestID)
		return
	}

	wh.logger.Infof("[REQUEST %s] Processing admission request for %s/%s of kind %s",
		requestID, admissionReview.Request.Namespace, admissionReview.Request.Name, admissionReview.Request.Kind.Kind)

	// Process the admission request
	response, podInfo, decision, err := wh.processAdmissionRequest(&admissionReview, requestID)
	if err != nil {
		wh.logger.Errorf("[REQUEST %s] Failed to process admission request: %v", requestID, err)
		wh.sendErrorResponse(w, "PROCESSING_ERROR", fmt.Sprintf("Failed to process admission request: %v", err), http.StatusInternalServerError, requestID)
		return
	}

	// Create admission review response
	admissionReview.Response = response
	admissionReview.Response.UID = admissionReview.Request.UID

	// Send response
	w.Header().Set(contentTypeHeader, contentTypeJSON)
	if err := json.NewEncoder(w).Encode(admissionReview); err != nil {
		wh.logger.Errorf("[REQUEST %s] Failed to encode response: %v", requestID, err)
		wh.sendErrorResponse(w, "ENCODE_ERROR", "Failed to encode response", http.StatusInternalServerError, requestID)
		return
	}

	duration := time.Since(startTime)
	wh.logger.Infof("[REQUEST %s] Admission request processed in %v, allowed: %t",
		requestID, duration, response.Allowed)

	// Record admission metrics
	violations := []string{}
	severity := "unknown"
	if decision != nil {
		severity = decision.Severity
	}
	if !response.Allowed && response.Result != nil {
		violations = []string{response.Result.Message}
	}
	wh.metrics.RecordAdmissionRequest(response.Allowed, duration, podInfo.Namespace, podInfo.Name, violations, severity)

	// Send notifications for security violations
	if !response.Allowed && wh.notifier != nil && wh.notifier.Enabled() {
		notification := &notifications.Notification{
			Type:      notifications.NotificationTypeSecurityAlert,
			Title:     "Container Security Violation Blocked",
			Message:   fmt.Sprintf("Pod %s/%s was blocked due to security violations", podInfo.Namespace, podInfo.Name),
			Severity:  severity,
			Timestamp: time.Now(),
			Details: map[string]interface{}{
				"namespace":  podInfo.Namespace,
				"pod_name":   podInfo.Name,
				"violations": strings.Join(violations, "; "),
				"reason":     response.Result.Message,
			},
		}

		if err := wh.notifier.Send(notification); err != nil {
			wh.logger.Errorf("[REQUEST %s] Failed to send notification: %v", requestID, err)
			// Don't fail the request if notification fails
		}
	}
}

// processAdmissionRequest processes the admission request and returns a decision
func (wh *WebhookHandler) processAdmissionRequest(admissionReview *admissionv1.AdmissionReview, requestID string) (*admissionv1.AdmissionResponse, *PodInfo, *ContainerSecurityDecision, error) {
	req := admissionReview.Request

	// Only process Pod creation/updates
	if req.Kind.Kind != "Pod" {
		wh.logger.Infof("[REQUEST %s] Allowing non-Pod resource: %s", requestID, req.Kind.Kind)
		return &admissionv1.AdmissionResponse{Allowed: true}, &PodInfo{Name: req.Name, Namespace: req.Namespace}, nil, nil
	}

	// Only process CREATE and UPDATE operations
	if req.Operation != admissionv1.Create && req.Operation != admissionv1.Update {
		wh.logger.Infof("[REQUEST %s] Allowing operation: %s", requestID, req.Operation)
		return &admissionv1.AdmissionResponse{Allowed: true}, &PodInfo{Name: req.Name, Namespace: req.Namespace}, nil, nil
	}

	// Parse the Pod object
	var pod corev1.Pod
	if _, _, err := wh.decoder.Decode(req.Object.Raw, nil, &pod); err != nil {
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Status:  "Failure",
				Message: fmt.Sprintf("Failed to decode Pod object: %v", err),
				Code:    http.StatusBadRequest,
			},
		}, &PodInfo{Name: req.Name, Namespace: req.Namespace}, nil, nil
	}

	// Validate the Pod with namespace context
	decision, err := wh.validatePod(&pod, req.Namespace, requestID)
	if err != nil {
		return &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Status:  "Failure",
				Message: fmt.Sprintf("Pod validation failed: %v", err),
				Code:    http.StatusInternalServerError,
			},
		}, &PodInfo{Name: pod.Name, Namespace: req.Namespace}, nil, nil
	}

	// Return admission response
	response := &admissionv1.AdmissionResponse{
		Allowed: decision.Allowed,
	}

	if !decision.Allowed {
		response.Result = &metav1.Status{
			Status:  "Failure",
			Message: decision.Reason,
			Code:    http.StatusForbidden,
		}
	}

	return response, &PodInfo{Name: pod.Name, Namespace: req.Namespace}, decision, nil
}

// validatePod performs security validation on a Pod
func (wh *WebhookHandler) validatePod(pod *corev1.Pod, namespace string, requestID string) (*ContainerSecurityDecision, error) {
	wh.logger.Infof("[REQUEST %s] Validating Pod %s/%s", requestID, namespace, pod.Name)

	decision := &ContainerSecurityDecision{
		Allowed:    true,
		Timestamp:  time.Now(),
		Violations: []string{},
	}

	// Extract container images
	images := wh.extractContainerImages(pod)
	if len(images) == 0 {
		decision.Reason = "No containers found in Pod"
		return decision, nil
	}

	wh.logger.Infof("[REQUEST %s] Found %d container images to validate", requestID, len(images))

	// Validate each image
	for _, image := range images {
		imageDecision, err := wh.validateImage(image, namespace, requestID)
		if err != nil {
			wh.logger.Errorf("[REQUEST %s] Failed to validate image %s: %v", requestID, image, err)
			decision.Allowed = false
			decision.Violations = append(decision.Violations, fmt.Sprintf("Failed to validate image %s: %v", image, err))
			continue
		}

		if !imageDecision.Allowed {
			decision.Allowed = false
			decision.Violations = append(decision.Violations, imageDecision.Violations...)
			if imageDecision.Severity == "CRITICAL" {
				decision.Severity = "CRITICAL"
				break // Critical violations block immediately
			}
		}
	}

	if !decision.Allowed {
		decision.Reason = fmt.Sprintf("Pod blocked due to security violations: %s", strings.Join(decision.Violations, "; "))
	}

	wh.logger.Infof("[REQUEST %s] Pod validation completed, allowed: %t, violations: %d",
		requestID, decision.Allowed, len(decision.Violations))

	return decision, nil
}

// validateImage performs security validation on a container image
func (wh *WebhookHandler) validateImage(image string, namespace string, requestID string) (*ContainerSecurityDecision, error) {
	decision := &ContainerSecurityDecision{
		Allowed:    true,
		Image:      image,
		Timestamp:  time.Now(),
		Violations: []string{},
	}

	// Step 1: Verify image signature
	wh.logger.Infof("[REQUEST %s] Verifying signature for image %s", requestID, image)
	signatureRequest := &cosign.VerificationRequest{
		Image: image,
	}
	signatureResult := &cosign.VerificationResult{
		Image:    image,
		Verified: false,
	}
	if wh.cosignVerifier != nil {
		sigResult, err := wh.cosignVerifier.Verify(context.Background(), signatureRequest)
		if err != nil {
			wh.logger.Errorf("[REQUEST %s] Signature verification failed for %s: %v", requestID, image, err)
			// For now, we'll continue with scanning even if signature verification fails
			// In production, this should be configurable
		} else {
			signatureResult = sigResult
		}
	} else {
		wh.logger.Warnf("[REQUEST %s] Cosign verifier not available, skipping signature verification", requestID)
	}

	// Step 2: Scan for vulnerabilities
	wh.logger.Infof("[REQUEST %s] Scanning image %s for vulnerabilities", requestID, image)
	scanResult := &scanner.ScanResult{
		Success:         false,
		Image:           image,
		ScanTime:        time.Now().Format(time.RFC3339),
		Vulnerabilities: []scanner.Vulnerability{},
		Summary:         scanner.VulnerabilitySummary{Total: 0},
	}
	if wh.trivyScanner != nil {
		scanRequest := &scanner.ScanRequest{
			Image: image,
		}
		result, err := wh.trivyScanner.Scan(context.Background(), scanRequest)
		if err != nil {
			wh.logger.Errorf("[REQUEST %s] Vulnerability scan failed for %s: %v", requestID, image, err)
			// Continue with empty scan results for demo purposes
		} else {
			scanResult = result
		}
	} else {
		wh.logger.Warnf("[REQUEST %s] Trivy scanner not available, using mock critical vulnerabilities for testing", requestID)
		// Mock critical vulnerabilities for testing webhook blocking
		scanResult = &scanner.ScanResult{
			Success:  true,
			Image:    image,
			ScanTime: time.Now().Format(time.RFC3339),
			Vulnerabilities: []scanner.Vulnerability{
				{
					ID:        "CVE-2023-TEST-001",
					Severity:  "CRITICAL",
					CVSSScore: 9.8,
					Package:   "test-package",
					Version:   "1.0.0",
				},
			},
			Summary: scanner.VulnerabilitySummary{
				Total:    1,
				Critical: 1,
				High:     0,
				Medium:   0,
				Low:      0,
				Unknown:  0,
			},
		}
	}

	// Step 3: Evaluate policies with OPA
	wh.logger.Infof("[REQUEST %s] Evaluating policies for image %s", requestID, image)

	// Convert scan results to OPA format
	opaScanResults := opa.ScanResults{
		Vulnerabilities: make([]opa.Vulnerability, len(scanResult.Vulnerabilities)),
		Summary: opa.VulnerabilitySummary{
			Total:    scanResult.Summary.Total,
			Critical: scanResult.Summary.Critical,
			High:     scanResult.Summary.High,
			Medium:   scanResult.Summary.Medium,
			Low:      scanResult.Summary.Low,
		},
	}

	for i, vuln := range scanResult.Vulnerabilities {
		opaScanResults.Vulnerabilities[i] = opa.Vulnerability{
			ID:        vuln.ID,
			Severity:  vuln.Severity,
			CVSSScore: vuln.CVSSScore,
			Package:   vuln.Package,
			Version:   vuln.Version,
		}
	}

	opaRequest := &opa.PolicyEvaluationRequest{
		Image:             image,
		ScanResults:       opaScanResults,
		SignatureVerified: signatureResult.Verified,
		DeploymentContext: opa.DeploymentContext{
			Namespace:   namespace,
			Environment: wh.getEnvironmentFromNamespace(namespace),
			Team:        wh.getTeamFromNamespace(namespace),
		},
	}

	policyResult, err := wh.opaEvaluator.EvaluatePolicy(context.Background(), opaRequest)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate policies: %w", err)
	}

	// Check policy violations
	if !policyResult.Allow {
		decision.Allowed = false
		decision.Reason = policyResult.Reason
		decision.Violations = append(decision.Violations, policyResult.Reason)
		if policyResult.Severity == "CRITICAL" {
			decision.Severity = "CRITICAL"
		}
	}

	return decision, nil
}

// extractContainerImages extracts all container images from a Pod
func (wh *WebhookHandler) extractContainerImages(pod *corev1.Pod) []string {
	var images []string

	// Extract from init containers
	for _, container := range pod.Spec.InitContainers {
		images = append(images, container.Image)
	}

	// Extract from regular containers
	for _, container := range pod.Spec.Containers {
		images = append(images, container.Image)
	}

	// Extract from ephemeral containers (if any)
	for _, container := range pod.Spec.EphemeralContainers {
		images = append(images, container.Image)
	}

	return images
}

// getEnvironmentFromNamespace determines the environment based on namespace naming conventions
func (wh *WebhookHandler) getEnvironmentFromNamespace(namespace string) string {
	switch {
	case strings.Contains(namespace, "prod"):
		return "production"
	case strings.Contains(namespace, "staging"):
		return "staging"
	case strings.Contains(namespace, "dev"):
		return "development"
	case strings.Contains(namespace, "test"):
		return "testing"
	default:
		return "production" // Default to production for security
	}
}

// getTeamFromNamespace determines the team based on namespace naming conventions
func (wh *WebhookHandler) getTeamFromNamespace(namespace string) string {
	// Simple team detection based on namespace prefixes
	// In production, this could be more sophisticated with labels or annotations
	if strings.Contains(namespace, "-") {
		parts := strings.Split(namespace, "-")
		if len(parts) > 0 {
			return parts[0]
		}
	}

	// Default team
	return "platform"
}

// validateAdmissionRequest validates the incoming HTTP request
func (wh *WebhookHandler) validateAdmissionRequest(r *http.Request) error {
	// Validate HTTP method
	if r.Method != http.MethodPost {
		return &WebhookError{
			Category: ErrorCategoryValidation,
			Code:     "INVALID_METHOD",
			Message:  fmt.Sprintf("only POST method is allowed, got %s", r.Method),
		}
	}

	// Validate Content-Type
	contentType := r.Header.Get(contentTypeHeader)
	if contentType != contentTypeJSON && contentType != "application/json; charset=utf-8" {
		return &WebhookError{
			Category: ErrorCategoryValidation,
			Code:     "INVALID_CONTENT_TYPE",
			Message:  fmt.Sprintf("invalid content-type: expected application/json, got %s", contentType),
		}
	}

	// Validate Content-Length
	if r.ContentLength < 0 {
		return &WebhookError{
			Category: ErrorCategoryValidation,
			Code:     "MISSING_CONTENT_LENGTH",
			Message:  "content-length header is required",
		}
	}

	if r.ContentLength > wh.config.MaxRequestSize {
		return &WebhookError{
			Category: ErrorCategoryValidation,
			Code:     "REQUEST_TOO_LARGE",
			Message: fmt.Sprintf("request body too large: %d bytes (max: %d bytes)",
				r.ContentLength, wh.config.MaxRequestSize),
		}
	}

	// Validate that body is not nil
	if r.Body == nil {
		return &WebhookError{
			Category: ErrorCategoryValidation,
			Code:     "MISSING_BODY",
			Message:  "request body is required",
		}
	}

	return nil
}

// handleWebhookError handles and logs webhook errors appropriately
func (wh *WebhookHandler) handleWebhookError(w http.ResponseWriter, err error, requestID string) {
	var webhookErr *WebhookError
	var ok bool

	if webhookErr, ok = err.(*WebhookError); !ok {
		// Wrap unknown errors as internal errors
		webhookErr = &WebhookError{
			Category: ErrorCategoryInternal,
			Code:     "INTERNAL_ERROR",
			Message:  "Internal server error",
			Cause:    err,
		}
	}

	// Log error with appropriate level based on category
	switch webhookErr.Category {
	case ErrorCategoryValidation:
		wh.logger.Warnf("[REQUEST %s] Validation error: %v", requestID, webhookErr)
	case ErrorCategorySecurity:
		wh.logger.Errorf("[REQUEST %s] Security error: %v", requestID, webhookErr)
	case ErrorCategoryProcessing:
		wh.logger.Errorf("[REQUEST %s] Processing error: %v", requestID, webhookErr)
	case ErrorCategoryInternal:
		wh.logger.Errorf("[REQUEST %s] Internal error: %v", requestID, webhookErr)
	default:
		wh.logger.Errorf("[REQUEST %s] Unknown error category %s: %v", requestID, webhookErr.Category, webhookErr)
	}

	// Determine HTTP status code based on error category
	statusCode := http.StatusInternalServerError
	switch webhookErr.Category {
	case ErrorCategoryValidation:
		statusCode = http.StatusBadRequest
	case ErrorCategorySecurity:
		statusCode = http.StatusForbidden
	case ErrorCategoryProcessing:
		statusCode = http.StatusUnprocessableEntity
	}

	wh.sendErrorResponse(w, webhookErr.Code, webhookErr.Message, statusCode, requestID)
}

// sendErrorResponse sends a standardized error response
func (wh *WebhookHandler) sendErrorResponse(w http.ResponseWriter, code, message string, statusCode int, requestID string) {
	w.Header().Set(contentTypeHeader, contentTypeJSON)
	w.WriteHeader(statusCode)

	errorResp := ErrorResponse{
		Code:      code,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	if err := json.NewEncoder(w).Encode(map[string]interface{}{
		"error": errorResp,
	}); err != nil {
		wh.logger.Errorf("[REQUEST %s] Failed to send error response: %v", requestID, err)
	}
}

// HealthCheckHandler provides health check endpoint for the webhook
func (wh *WebhookHandler) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set(contentTypeHeader, contentTypeJSON)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "healthy",
		"service":   "admission-webhook",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	})
}
