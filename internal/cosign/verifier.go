package cosign

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"container-security-mts/pkg/utils"
)

// CosignVerifier handles container image signature verification operations
type CosignVerifier struct {
	config *Config
	logger *utils.Logger
}

// Config holds cosign verifier configuration
type Config struct {
	Cosign struct {
		Timeout        time.Duration `yaml:"timeout" json:"timeout"`
		AllowUnsigned  bool          `yaml:"allow_unsigned" json:"allow_unsigned"`
		Keyless        bool          `yaml:"keyless" json:"keyless"`
		PublicKeyPath  string        `yaml:"public_key_path" json:"public_key_path"`
		CertIdentity   string        `yaml:"cert_identity" json:"cert_identity"`
		CertOIDCIssuer string        `yaml:"cert_oidc_issuer" json:"cert_oidc_issuer"`
		FulcioURL      string        `yaml:"fulcio_url" json:"fulcio_url"`
		RekorURL       string        `yaml:"rekor_url" json:"rekor_url"`
	} `yaml:"cosign" json:"cosign"`
}

// VerificationRequest represents a signature verification request
type VerificationRequest struct {
	Image string `json:"image"`
}

// VerificationResult represents the result of signature verification
type VerificationResult struct {
	Image           string    `json:"image"`
	Verified        bool      `json:"verified"`
	SignatureCount  int       `json:"signature_count"`
	CertificateInfo string    `json:"certificate_info,omitempty"`
	Error           string    `json:"error,omitempty"`
	Timestamp       time.Time `json:"timestamp"`
}

// NewCosignVerifier creates a new Cosign verifier instance
func NewCosignVerifier(config *Config, logger *utils.Logger) (*CosignVerifier, error) {
	verifier := &CosignVerifier{
		config: config,
		logger: logger,
	}

	return verifier, nil
}

// DefaultConfig returns default cosign verifier configuration
func DefaultConfig() *Config {
	config := &Config{}

	// Cosign defaults
	config.Cosign.Timeout = 30 * time.Second
	config.Cosign.AllowUnsigned = false
	config.Cosign.Keyless = true
	config.Cosign.FulcioURL = "https://fulcio.sigstore.dev"
	config.Cosign.RekorURL = "https://rekor.sigstore.dev"

	return config
}

// LoadConfig loads configuration from file (placeholder for future implementation)
func LoadConfig(path string) (*Config, error) {
	// For now, return default config
	// TODO: Implement YAML/JSON config loading in future iterations
	return DefaultConfig(), nil
}

// Verify verifies container image signatures
func (cv *CosignVerifier) Verify(ctx context.Context, req *VerificationRequest) (*VerificationResult, error) {
	startTime := time.Now()
	result := &VerificationResult{
		Image:     req.Image,
		Verified:  false,
		Timestamp: startTime,
	}

	cv.logger.Infof("Starting signature verification for image: %s", req.Image)

	// Validate request
	if err := cv.validateRequest(req); err != nil {
		return nil, fmt.Errorf("invalid request: %w", err)
	}

	// Execute verification
	verified, signatureCount, certInfo, err := cv.executeVerification(ctx, req)
	if err != nil {
		result.Error = err.Error()
		return result, err
	}

	// Process results
	result.Verified = verified
	result.SignatureCount = signatureCount
	result.CertificateInfo = certInfo

	cv.logger.Infof("Signature verification completed for %s: verified=%v, signatures=%d",
		req.Image, verified, signatureCount)

	return result, nil
}

// VerifyHandler handles HTTP signature verification requests
func (cv *CosignVerifier) VerifyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req VerificationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		cv.logger.Errorf("Failed to decode request: %v", err)
		cv.sendErrorResponse(w, "INVALID_REQUEST", "Failed to decode request body", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), cv.config.Cosign.Timeout)
	defer cancel()

	result, err := cv.Verify(ctx, &req)
	if err != nil {
		cv.logger.Errorf("Signature verification failed: %v", err)
		cv.sendErrorResponse(w, result.Error, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// HealthCheck performs a health check on cosign
func (cv *CosignVerifier) HealthCheck() error {
	// Check if cosign command is available
	cmd := exec.Command("cosign", "version")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("cosign command not available: %w", err)
	}

	return nil
}

// validateRequest validates verification request parameters
func (cv *CosignVerifier) validateRequest(req *VerificationRequest) error {
	if req.Image == "" {
		return fmt.Errorf("image is required")
	}

	// Validate image format (basic check)
	if !strings.Contains(req.Image, ":") && !strings.Contains(req.Image, "@") {
		return fmt.Errorf("invalid image format: %s", req.Image)
	}

	return nil
}

// executeVerification runs the actual cosign verify command
func (cv *CosignVerifier) executeVerification(ctx context.Context, req *VerificationRequest) (bool, int, string, error) {
	// Build cosign command arguments
	args := []string{"verify"}

	// Add verification options based on configuration
	if cv.config.Cosign.Keyless {
		if cv.config.Cosign.CertIdentity != "" {
			args = append(args, "--certificate-identity", cv.config.Cosign.CertIdentity)
		}
		if cv.config.Cosign.CertOIDCIssuer != "" {
			args = append(args, "--certificate-oidc-issuer", cv.config.Cosign.CertOIDCIssuer)
		}
		// For broad keyless verification (default)
		if cv.config.Cosign.CertIdentity == "" && cv.config.Cosign.CertOIDCIssuer == "" {
			args = append(args, "--certificate-identity-regexp", ".*")
			args = append(args, "--certificate-oidc-issuer-regexp", ".*")
		}
	} else if cv.config.Cosign.PublicKeyPath != "" {
		args = append(args, "--key", cv.config.Cosign.PublicKeyPath)
	}

	args = append(args, req.Image)

	// Execute command
	cv.logger.Debugf("Executing: cosign %s", strings.Join(args, " "))
	cmd := exec.CommandContext(ctx, "cosign", args...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		// Check if image is unsigned
		errorOutput := stderr.String()
		if cv.isUnsignedImageError(errorOutput) {
			if cv.config.Cosign.AllowUnsigned {
				cv.logger.Warnf("Image %s is unsigned but allowing as configured", req.Image)
				return false, 0, "", nil
			}
			return false, 0, "", fmt.Errorf("image is unsigned: %s", req.Image)
		}
		return false, 0, "", fmt.Errorf("verification failed: %w, stderr: %s", err, errorOutput)
	}

	// Parse successful verification output
	output := stdout.String()
	signatureCount := cv.parseSignatureCount(output)
	certInfo := cv.extractCertificateInfo(output)

	return true, signatureCount, certInfo, nil
}

// isUnsignedImageError checks if the error indicates an unsigned image
func (cv *CosignVerifier) isUnsignedImageError(errorOutput string) bool {
	lowerOutput := strings.ToLower(errorOutput)
	return strings.Contains(lowerOutput, "no signatures found") ||
		strings.Contains(lowerOutput, "none of the signatures were verified") ||
		strings.Contains(lowerOutput, "no matching signatures")
}

// parseSignatureCount extracts signature count from verification output
func (cv *CosignVerifier) parseSignatureCount(output string) int {
	// Simple heuristic: count occurrences of "Verification for"
	count := strings.Count(output, "Verification for")
	if count == 0 {
		// If no explicit count, assume at least 1 if verification succeeded
		return 1
	}
	return count
}

// extractCertificateInfo extracts certificate information from verification output
func (cv *CosignVerifier) extractCertificateInfo(output string) string {
	// Extract lines containing certificate information
	lines := strings.Split(output, "\n")
	var certLines []string

	for _, line := range lines {
		if strings.Contains(line, "Certificate") || strings.Contains(line, "Issuer") {
			certLines = append(certLines, strings.TrimSpace(line))
		}
	}

	return strings.Join(certLines, "; ")
}

// sendErrorResponse sends a standardized error response
func (cv *CosignVerifier) sendErrorResponse(w http.ResponseWriter, code, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	errorResp := struct {
		Error struct {
			Code      string    `json:"code"`
			Message   string    `json:"message"`
			Timestamp time.Time `json:"timestamp"`
		} `json:"error"`
	}{
		Error: struct {
			Code      string    `json:"code"`
			Message   string    `json:"message"`
			Timestamp time.Time `json:"timestamp"`
		}{
			Code:      code,
			Message:   message,
			Timestamp: time.Now().UTC(),
		},
	}

	json.NewEncoder(w).Encode(errorResp)
}
