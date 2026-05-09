package opa

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"container-security-mts/pkg/utils"
)

const (
	contentTypeHeader    = "Content-Type"
	contentTypeJSON      = "application/json"
	opaStatusErrorFormat = "OPA returned status %d"
)

// NewOPAEvaluator creates a new OPA evaluator instance
func NewOPAEvaluator(config *Config, logger *utils.Logger) (*OPAEvaluator, error) {
	evaluator := &OPAEvaluator{
		config: config,
		logger: logger,
	}

	return evaluator, nil
}

// DefaultConfig returns default OPA evaluator configuration
func DefaultConfig() *Config {
	config := &Config{}

	// OPA defaults
	config.OPA.URL = "http://localhost:8181"
	config.OPA.PoliciesPath = "/opt/opa/policies"
	config.OPA.DataPath = "/opt/opa/data"
	config.OPA.Timeout = 30 * time.Second
	config.OPA.RetryAttempts = 3
	config.OPA.RetryDelay = 1 * time.Second

	return config
}

// EvaluatePolicy evaluates container security policies
func (e *OPAEvaluator) EvaluatePolicy(ctx context.Context, req *PolicyEvaluationRequest) (*PolicyEvaluationResult, error) {
	e.logger.Infof("Evaluating policies for image: %s", req.Image)

	// If OPA URL is not configured, use local evaluation
	if e.config.OPA.URL == "" {
		return e.evaluatePolicyLocally(ctx, req)
	}

	// Prepare OPA query payload
	payload := map[string]interface{}{
		"input": req,
	}

	// Make request to OPA
	result, err := e.queryOPA(ctx, "container_security", payload)
	if err != nil {
		e.logger.Errorf("Policy evaluation failed: %v", err)
		// Fallback to local evaluation if OPA server is not available
		e.logger.Warnf("Falling back to local policy evaluation")
		return e.evaluatePolicyLocally(ctx, req)
	}

	// Parse result
	evalResult, err := e.parseEvaluationResult(result)
	if err != nil {
		e.logger.Errorf("Failed to parse evaluation result: %v", err)
		// Fallback to local evaluation if parsing fails
		e.logger.Warnf("Falling back to local policy evaluation due to parsing error")
		return e.evaluatePolicyLocally(ctx, req)
	}

	e.logger.Infof("Policy evaluation completed for %s: allow=%v", req.Image, evalResult.Allow)
	return evalResult, nil
}

// evaluatePolicyLocally performs local policy evaluation when OPA server is not available
func (e *OPAEvaluator) evaluatePolicyLocally(ctx context.Context, req *PolicyEvaluationRequest) (*PolicyEvaluationResult, error) {
	e.logger.Infof("Performing local policy evaluation for image: %s", req.Image)

	result := &PolicyEvaluationResult{
		Allow:    true,
		PolicyID: "local_policy",
	}

	// Check for critical vulnerabilities
	if req.ScanResults.Summary.Critical > 0 {
		result.Allow = false
		result.Reason = fmt.Sprintf("Image blocked due to %d critical vulnerabilities", req.ScanResults.Summary.Critical)
		result.Severity = "CRITICAL"
		return result, nil
	}

	// Check for high vulnerabilities (limit to 5)
	if req.ScanResults.Summary.High > 5 {
		result.Allow = false
		result.Reason = fmt.Sprintf("Image blocked due to %d high-severity vulnerabilities (max allowed: 5)", req.ScanResults.Summary.High)
		result.Severity = "HIGH"
		return result, nil
	}

	// Check signature verification for production environments
	if req.DeploymentContext.Environment == "production" && !req.SignatureVerified {
		result.Allow = false
		result.Reason = "Image blocked: signature verification required for production environment"
		result.Severity = "HIGH"
		return result, nil
	}

	// Basic checks passed
	result.Reason = "Image passed local policy evaluation"

	e.logger.Infof("Local policy evaluation completed for %s: allow=%v", req.Image, result.Allow)
	return result, nil
}

// EvaluatePolicyHandler handles HTTP policy evaluation requests
func (e *OPAEvaluator) EvaluatePolicyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req PolicyEvaluationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		e.logger.Errorf("Failed to decode request: %v", err)
		e.sendErrorResponse(w, "INVALID_REQUEST", "Failed to decode request body", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), e.config.OPA.Timeout)
	defer cancel()

	result, err := e.EvaluatePolicy(ctx, &req)
	if err != nil {
		e.logger.Errorf("Policy evaluation failed: %v", err)
		e.sendErrorResponse(w, "EVALUATION_FAILED", err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set(contentTypeHeader, contentTypeJSON)
	json.NewEncoder(w).Encode(result)
}

// UpdatePolicy updates OPA policies dynamically
func (e *OPAEvaluator) UpdatePolicy(ctx context.Context, req *PolicyUpdateRequest) error {
	e.logger.Infof("Updating policy: %s", req.PolicyName)

	// Prepare policy update payload
	payload := map[string]interface{}{
		"rego": req.PolicyData,
	}

	if req.Data != nil {
		payload["data"] = req.Data
	}

	// Update policy via OPA API
	url := fmt.Sprintf("%s/v1/policies/%s", e.config.OPA.URL, req.PolicyName)
	if err := e.putOPA(ctx, url, payload); err != nil {
		e.logger.Errorf("Policy update failed: %v", err)
		return fmt.Errorf("policy update failed: %w", err)
	}

	e.logger.Infof("Policy %s updated successfully", req.PolicyName)
	return nil
}

// HealthCheck performs a health check on OPA
func (e *OPAEvaluator) HealthCheck() error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", e.config.OPA.URL+"/health", nil)
	if err != nil {
		return fmt.Errorf("failed to create health check request: %w", err)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("OPA health check failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("OPA returned status %d", resp.StatusCode)
	}

	return nil
}

// queryOPA queries OPA with the given data
func (e *OPAEvaluator) queryOPA(ctx context.Context, path string, data interface{}) (interface{}, error) {
	var lastErr error

	for attempt := 1; attempt <= e.config.OPA.RetryAttempts; attempt++ {
		result, err := e.doQueryOPA(ctx, path, data)
		if err == nil {
			return result, nil
		}

		lastErr = err
		e.logger.Warnf("OPA query attempt %d failed: %v", attempt, err)

		if attempt < e.config.OPA.RetryAttempts {
			time.Sleep(e.config.OPA.RetryDelay)
		}
	}

	return nil, fmt.Errorf("all OPA query attempts failed: %w", lastErr)
}

// doQueryOPA performs the actual OPA query
func (e *OPAEvaluator) doQueryOPA(ctx context.Context, path string, data interface{}) (interface{}, error) {
	// Serialize request data
	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request data: %w", err)
	}

	// Create request
	url := fmt.Sprintf("%s/v1/data/%s", e.config.OPA.URL, path)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set(contentTypeHeader, contentTypeJSON)

	// Execute request
	client := &http.Client{Timeout: e.config.OPA.Timeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf(opaStatusErrorFormat, resp.StatusCode)
	}

	// Parse response
	var result interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

// putOPA performs a PUT request to OPA
func (e *OPAEvaluator) putOPA(ctx context.Context, url string, data interface{}) error {
	// Serialize request data
	jsonData, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("failed to marshal request data: %w", err)
	}

	// Create request
	req, err := http.NewRequestWithContext(ctx, "PUT", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set(contentTypeHeader, contentTypeJSON)

	// Execute request
	client := &http.Client{Timeout: e.config.OPA.Timeout}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf(opaStatusErrorFormat, resp.StatusCode)
	}

	return nil
}

// parseEvaluationResult parses the OPA evaluation result
func (e *OPAEvaluator) parseEvaluationResult(result interface{}) (*PolicyEvaluationResult, error) {
	resultMap, ok := result.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid result format")
	}

	resultArray, ok := resultMap["result"].([]interface{})
	if !ok || len(resultArray) == 0 {
		return nil, fmt.Errorf("no evaluation results found")
	}

	expressions, ok := resultArray[0].(map[string]interface{})["expressions"].([]interface{})
	if !ok || len(expressions) == 0 {
		return nil, fmt.Errorf("no expressions found in result")
	}

	expression := expressions[0].(map[string]interface{})
	value, ok := expression["value"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("no value found in expression")
	}

	evalResult := &PolicyEvaluationResult{}

	// Parse allow decision
	if allow, ok := value["allow"].(bool); ok {
		evalResult.Allow = allow
	}

	// Parse reason
	if reason, ok := value["reason"].(string); ok {
		evalResult.Reason = reason
	}

	// Parse policy ID
	if policyID, ok := value["policy_id"].(string); ok {
		evalResult.PolicyID = policyID
	}

	// Parse severity
	if severity, ok := value["severity"].(string); ok {
		evalResult.Severity = severity
	}

	return evalResult, nil
}

// sendErrorResponse sends a standardized error response
func (e *OPAEvaluator) sendErrorResponse(w http.ResponseWriter, code, message string, statusCode int) {
	w.Header().Set(contentTypeHeader, contentTypeJSON)
	w.WriteHeader(statusCode)

	errorResp := PolicyEvaluationError{
		Code:      code,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"allow": false,
		"error": errorResp,
	})
}
