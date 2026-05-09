package v1

import (
	"time"

	admissionv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// SuccessResponse represents a standardized success response
type SuccessResponse struct {
	Code      string      `json:"code"`
	Message   string      `json:"message"`
	Data      interface{} `json:"data,omitempty"`
	Timestamp string      `json:"timestamp"`
}

// AdmissionWebhookRequest represents the incoming admission webhook request
type AdmissionWebhookRequest struct {
	Kind               string                       `json:"kind"`
	Name               string                       `json:"name"`
	Namespace          string                       `json:"namespace"`
	Operation          string                       `json:"operation"`
	Object             runtime.RawExtension         `json:"object"`
	OldObject          runtime.RawExtension         `json:"oldObject,omitempty"`
	DryRun             *bool                        `json:"dryRun,omitempty"`
	Options            runtime.RawExtension         `json:"options,omitempty"`
	RequestKind        *metav1.GroupVersionKind     `json:"requestKind,omitempty"`
	RequestResource    *metav1.GroupVersionResource `json:"requestResource,omitempty"`
	RequestSubResource string                       `json:"requestSubResource,omitempty"`
	SubResource        string                       `json:"subResource,omitempty"`
}

// AdmissionWebhookResponse represents the response from the admission webhook
type AdmissionWebhookResponse struct {
	Allowed          bool                   `json:"allowed"`
	Status           *metav1.Status         `json:"status,omitempty"`
	Patch            []byte                 `json:"patch,omitempty"`
	PatchType        *admissionv1.PatchType `json:"patchType,omitempty"`
	AuditAnnotations map[string]string      `json:"auditAnnotations,omitempty"`
	Warnings         []string               `json:"warnings,omitempty"`
}

// ContainerSecurityDecision represents the result of security evaluation
type ContainerSecurityDecision struct {
	Allowed    bool      `json:"allowed"`
	Reason     string    `json:"reason"`
	Severity   string    `json:"severity,omitempty"`
	Violations []string  `json:"violations,omitempty"`
	Image      string    `json:"image,omitempty"`
	Timestamp  time.Time `json:"timestamp"`
}

// SecurityScanRequest represents a request to scan a container image
type SecurityScanRequest struct {
	Image    string            `json:"image"`
	Registry string            `json:"registry,omitempty"`
	Tag      string            `json:"tag,omitempty"`
	Options  map[string]string `json:"options,omitempty"`
}

// SecurityScanResult represents the result of a security scan
type SecurityScanResult struct {
	Image           string          `json:"image"`
	Vulnerabilities []Vulnerability `json:"vulnerabilities"`
	Severity        string          `json:"severity"`
	TotalCount      int             `json:"totalCount"`
	CriticalCount   int             `json:"criticalCount"`
	HighCount       int             `json:"highCount"`
	MediumCount     int             `json:"mediumCount"`
	LowCount        int             `json:"lowCount"`
	ScanTime        time.Duration   `json:"scanTime"`
	Timestamp       time.Time       `json:"timestamp"`
}

// SignatureVerificationRequest represents a request to verify image signatures
type SignatureVerificationRequest struct {
	Image   string `json:"image"`
	KeyPath string `json:"keyPath,omitempty"`
	KeyData string `json:"keyData,omitempty"`
}

// SignatureVerificationResult represents the result of signature verification
type SignatureVerificationResult struct {
	Image     string    `json:"image"`
	Verified  bool      `json:"verified"`
	Signature string    `json:"signature,omitempty"`
	Error     string    `json:"error,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}

// PolicyEvaluationRequest represents a request to evaluate policies
type PolicyEvaluationRequest struct {
	ScanResult      *SecurityScanResult          `json:"scanResult,omitempty"`
	SignatureResult *SignatureVerificationResult `json:"signatureResult,omitempty"`
	Pod             *corev1.Pod                  `json:"pod,omitempty"`
	AdditionalData  map[string]interface{}       `json:"additionalData,omitempty"`
}

// PolicyEvaluationResult represents the result of policy evaluation
type PolicyEvaluationResult struct {
	Allowed       bool              `json:"allowed"`
	Violations    []PolicyViolation `json:"violations,omitempty"`
	PolicyResults []PolicyResult    `json:"policyResults,omitempty"`
	Timestamp     time.Time         `json:"timestamp"`
}

// PolicyViolation represents a policy violation
type PolicyViolation struct {
	PolicyName string `json:"policyName"`
	Rule       string `json:"rule"`
	Message    string `json:"message"`
	Severity   string `json:"severity"`
	Resource   string `json:"resource,omitempty"`
}

// PolicyResult represents the result of evaluating a single policy
type PolicyResult struct {
	PolicyName string                 `json:"policyName"`
	Passed     bool                   `json:"passed"`
	Result     map[string]interface{} `json:"result,omitempty"`
	Error      string                 `json:"error,omitempty"`
}

// PodInfo represents basic pod information for metrics
type PodInfo struct {
	Name      string
	Namespace string
}

// WebhookConfig represents the configuration for the admission webhook
type WebhookConfig struct {
	Port           int           `yaml:"port" json:"port"`
	Host           string        `yaml:"host" json:"host"`
	CertFile       string        `yaml:"certFile" json:"certFile"`
	KeyFile        string        `yaml:"keyFile" json:"keyFile"`
	TLSEnabled     bool          `yaml:"tlsEnabled" json:"tlsEnabled"`
	ReadTimeout    time.Duration `yaml:"readTimeout" json:"readTimeout"`
	WriteTimeout   time.Duration `yaml:"writeTimeout" json:"writeTimeout"`
	IdleTimeout    time.Duration `yaml:"idleTimeout" json:"idleTimeout"`
	MaxRequestSize int64         `yaml:"maxRequestSize" json:"maxRequestSize"`
	ValidationMode string        `yaml:"validationMode" json:"validationMode"`
}
