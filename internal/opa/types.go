package opa

import (
	"time"

	"container-security-mts/pkg/utils"
)

// OPAEvaluator handles OPA policy evaluation operations
type OPAEvaluator struct {
	config *Config
	logger *utils.Logger
}

// Config holds OPA evaluator configuration
type Config struct {
	OPA struct {
		URL           string        `yaml:"url" json:"url"`
		PoliciesPath  string        `yaml:"policies_path" json:"policies_path"`
		DataPath      string        `yaml:"data_path" json:"data_path"`
		Timeout       time.Duration `yaml:"timeout" json:"timeout"`
		RetryAttempts int           `yaml:"retry_attempts" json:"retry_attempts"`
		RetryDelay    time.Duration `yaml:"retry_delay" json:"retry_delay"`
	} `yaml:"opa" json:"opa"`
}

// PolicyEvaluationRequest represents a policy evaluation request
type PolicyEvaluationRequest struct {
	Image             string            `json:"image"`
	ScanResults       ScanResults       `json:"scan_results"`
	SignatureVerified bool              `json:"signature_verified"`
	DeploymentContext DeploymentContext `json:"deployment_context"`
}

// ScanResults represents scan results from Trivy
type ScanResults struct {
	Vulnerabilities []Vulnerability      `json:"vulnerabilities"`
	Summary         VulnerabilitySummary `json:"summary"`
}

// Vulnerability represents a single vulnerability
type Vulnerability struct {
	ID        string  `json:"id"`
	Severity  string  `json:"severity"`
	CVSSScore float64 `json:"cvss_score"`
	Package   string  `json:"package"`
	Version   string  `json:"version"`
}

// VulnerabilitySummary provides a summary of vulnerabilities by severity
type VulnerabilitySummary struct {
	Total    int `json:"total"`
	Critical int `json:"critical"`
	High     int `json:"high"`
	Medium   int `json:"medium"`
	Low      int `json:"low"`
}

// DeploymentContext represents deployment context information
type DeploymentContext struct {
	Namespace   string `json:"namespace"`
	Environment string `json:"environment"`
	Team        string `json:"team"`
}

// PolicyEvaluationResult represents the result of policy evaluation
type PolicyEvaluationResult struct {
	Allow    bool   `json:"allow"`
	Reason   string `json:"reason,omitempty"`
	PolicyID string `json:"policy_id,omitempty"`
	Severity string `json:"severity,omitempty"`
}

// PolicyEvaluationError represents a policy evaluation error
type PolicyEvaluationError struct {
	Code      string                 `json:"code"`
	Message   string                 `json:"message"`
	Details   map[string]interface{} `json:"details,omitempty"`
	Timestamp string                 `json:"timestamp"`
}

// PolicyUpdateRequest represents a policy update request
type PolicyUpdateRequest struct {
	PolicyName string                 `json:"policy_name"`
	PolicyData string                 `json:"policy_data"`
	Data       map[string]interface{} `json:"data,omitempty"`
}
