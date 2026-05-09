package scanner

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

// TrivyScanner handles container image scanning operations
type TrivyScanner struct {
	config *Config
	logger *utils.Logger
}

// Config holds scanner configuration
type Config struct {
	Trivy struct {
		CacheDir       string        `yaml:"cache_dir" json:"cache_dir"`
		ReportsDir     string        `yaml:"reports_dir" json:"reports_dir"`
		Timeout        time.Duration `yaml:"timeout" json:"timeout"`
		SkipDBUpdate   bool          `yaml:"skip_db_update" json:"skip_db_update"`
		UpdateInterval time.Duration `yaml:"update_interval" json:"update_interval"`
	} `yaml:"trivy" json:"trivy"`
	Server struct {
		ReadTimeout  time.Duration `yaml:"read_timeout" json:"read_timeout"`
		WriteTimeout time.Duration `yaml:"write_timeout" json:"write_timeout"`
		IdleTimeout  time.Duration `yaml:"idle_timeout" json:"idle_timeout"`
	} `yaml:"server" json:"server"`
}

// ScanRequest represents a scan request
type ScanRequest struct {
	Image          string   `json:"image"`
	ScanTypes      []string `json:"scan_types,omitempty"`
	SeverityLevels []string `json:"severity_levels,omitempty"`
	Format         string   `json:"format,omitempty"`
	SkipDBUpdate   bool     `json:"skip_db_update,omitempty"`
}

// ScanResult represents the result of a scan
type ScanResult struct {
	Success         bool                 `json:"success"`
	Image           string               `json:"image"`
	ScanTime        string               `json:"scan_time"`
	StartTime       string               `json:"start_time,omitempty"`
	Vulnerabilities []Vulnerability      `json:"vulnerabilities"`
	Summary         VulnerabilitySummary `json:"summary"`
	ReportFile      string               `json:"report_file,omitempty"`
	Error           *ScanError           `json:"error,omitempty"`
}

// Vulnerability represents a single vulnerability
type Vulnerability struct {
	ID           string  `json:"id"`
	Severity     string  `json:"severity"`
	CVSSScore    float64 `json:"cvss_score"`
	Package      string  `json:"package"`
	Version      string  `json:"version"`
	FixedVersion string  `json:"fixed_version,omitempty"`
	Description  string  `json:"description"`
}

// VulnerabilitySummary provides a summary of vulnerabilities by severity
type VulnerabilitySummary struct {
	Total    int `json:"total"`
	Critical int `json:"critical"`
	High     int `json:"high"`
	Medium   int `json:"medium"`
	Low      int `json:"low"`
	Unknown  int `json:"unknown"`
}

// ScanError represents a scan error
type ScanError struct {
	Code      string                 `json:"code"`
	Message   string                 `json:"message"`
	Details   map[string]interface{} `json:"details,omitempty"`
	Timestamp string                 `json:"timestamp"`
}

// NewTrivyScanner creates a new Trivy scanner instance
func NewTrivyScanner(config *Config, logger *utils.Logger) (*TrivyScanner, error) {
	scanner := &TrivyScanner{
		config: config,
		logger: logger,
	}

	// Ensure directories exist
	if err := ensureDirectories(config); err != nil {
		return nil, fmt.Errorf("failed to create directories: %w", err)
	}

	// Start background database update routine
	if !config.Trivy.SkipDBUpdate {
		go scanner.startDBUpdateRoutine()
	}

	return scanner, nil
}

// DefaultConfig returns default scanner configuration
func DefaultConfig() *Config {
	config := &Config{}

	// Trivy defaults
	config.Trivy.CacheDir = "/opt/trivy/cache"
	config.Trivy.ReportsDir = "/opt/trivy/reports"
	config.Trivy.Timeout = 5 * time.Minute
	config.Trivy.SkipDBUpdate = false
	config.Trivy.UpdateInterval = 24 * time.Hour

	// Server defaults
	config.Server.ReadTimeout = 10 * time.Second
	config.Server.WriteTimeout = 10 * time.Second
	config.Server.IdleTimeout = 120 * time.Second

	return config
}

// LoadConfig loads configuration from file (placeholder for future implementation)
func LoadConfig(path string) (*Config, error) {
	// For now, return default config
	// TODO: Implement YAML/JSON config loading
	return DefaultConfig(), nil
}

// Scan performs a vulnerability scan on a container image
func (s *TrivyScanner) Scan(ctx context.Context, req *ScanRequest) (*ScanResult, error) {
	startTime := time.Now().UTC()
	result := &ScanResult{
		Image:     req.Image,
		StartTime: startTime.Format(time.RFC3339),
	}

	s.logger.Infof("Starting scan for image: %s", req.Image)

	// Validate request
	if err := s.validateRequest(req); err != nil {
		return nil, fmt.Errorf("invalid request: %w", err)
	}

	// Update database if needed
	if !req.SkipDBUpdate && !s.config.Trivy.SkipDBUpdate {
		if err := s.updateDatabase(ctx); err != nil {
			s.logger.Warnf("Failed to update vulnerability database: %v", err)
		}
	}

	// Execute scan
	vulns, reportFile, err := s.executeScan(ctx, req)
	if err != nil {
		result.Error = &ScanError{
			Code:      "SCAN_FAILED",
			Message:   err.Error(),
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}
		return result, err
	}

	// Process results
	result.Success = true
	result.ScanTime = time.Now().UTC().Format(time.RFC3339)
	result.Vulnerabilities = vulns
	result.Summary = s.summarizeVulnerabilities(vulns)
	result.ReportFile = reportFile

	s.logger.Infof("Scan completed for %s: %d vulnerabilities found", req.Image, len(vulns))

	return result, nil
}

// ScanHandler handles HTTP scan requests
func (s *TrivyScanner) ScanHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.logger.Errorf("Failed to decode request: %v", err)
		s.sendErrorResponse(w, "INVALID_REQUEST", "Failed to decode request body", http.StatusBadRequest)
		return
	}

	// Set defaults
	if req.ScanTypes == nil {
		req.ScanTypes = []string{"os", "library"}
	}
	if req.SeverityLevels == nil {
		req.SeverityLevels = []string{"CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"}
	}
	if req.Format == "" {
		req.Format = "json"
	}

	ctx, cancel := context.WithTimeout(r.Context(), s.config.Trivy.Timeout)
	defer cancel()

	result, err := s.Scan(ctx, &req)
	if err != nil {
		s.logger.Errorf("Scan failed: %v", err)
		s.sendErrorResponse(w, result.Error.Code, result.Error.Message, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// HealthCheck performs a health check
func (s *TrivyScanner) HealthCheck() error {
	// Check if trivy command is available
	cmd := exec.Command("trivy", "--version")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("trivy command not available: %w", err)
	}

	// Check if cache directory is writable
	if err := exec.Command("touch", s.config.Trivy.CacheDir+"/.health").Run(); err != nil {
		return fmt.Errorf("cache directory not writable: %w", err)
	}

	return nil
}

// validateRequest validates scan request parameters
func (s *TrivyScanner) validateRequest(req *ScanRequest) error {
	if req.Image == "" {
		return fmt.Errorf("image is required")
	}

	// Validate scan types
	validScanTypes := map[string]bool{"os": true, "library": true}
	for _, scanType := range req.ScanTypes {
		if !validScanTypes[scanType] {
			return fmt.Errorf("invalid scan type: %s", scanType)
		}
	}

	// Validate severity levels
	validSeverities := map[string]bool{
		"CRITICAL": true, "HIGH": true, "MEDIUM": true, "LOW": true, "UNKNOWN": true,
	}
	for _, severity := range req.SeverityLevels {
		if !validSeverities[severity] {
			return fmt.Errorf("invalid severity level: %s", severity)
		}
	}

	// Validate format
	if req.Format != "" && req.Format != "json" && req.Format != "sarif" {
		return fmt.Errorf("invalid format: %s", req.Format)
	}

	return nil
}

// executeScan runs the actual trivy scan command
func (s *TrivyScanner) executeScan(ctx context.Context, req *ScanRequest) ([]Vulnerability, string, error) {
	// Create report file
	reportFile := fmt.Sprintf("%s/scan_%d.json",
		s.config.Trivy.ReportsDir,
		time.Now().Unix(),
	)

	// Build trivy command arguments
	args := []string{
		"--cache-dir", s.config.Trivy.CacheDir,
		"--format", req.Format,
		"--output", reportFile,
		"--scanners", "vuln",
	}

	// Add severity filter
	if len(req.SeverityLevels) > 0 {
		args = append(args, "--severity", strings.Join(req.SeverityLevels, ","))
	}

	// Add scan types (for future trivy versions)
	// Currently trivy doesn't have explicit scan type flags, but keeping for future compatibility

	args = append(args, "image", req.Image)

	// Execute command
	s.logger.Debugf("Executing: trivy %s", strings.Join(args, " "))
	cmd := exec.CommandContext(ctx, "trivy", args...)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, "", fmt.Errorf("trivy scan failed: %w, stderr: %s", err, stderr.String())
	}

	// Parse results
	vulns, err := s.parseScanResults(reportFile, req.Format)
	if err != nil {
		return nil, "", fmt.Errorf("failed to parse scan results: %w", err)
	}

	return vulns, reportFile, nil
}

// parseScanResults parses the trivy output file
func (s *TrivyScanner) parseScanResults(reportFile, format string) ([]Vulnerability, error) {
	if format != "json" {
		return nil, fmt.Errorf("only JSON format is supported for parsing")
	}

	// Read and parse JSON file
	data, err := exec.Command("cat", reportFile).Output()
	if err != nil {
		return nil, fmt.Errorf("failed to read report file: %w", err)
	}

	var trivyReport struct {
		Results []struct {
			Vulnerabilities []struct {
				VulnerabilityID string `json:"VulnerabilityID"`
				Severity        string `json:"Severity"`
				CVSS            struct {
					NVD struct {
						V3Score *float64 `json:"V3Score"`
						V2Score *float64 `json:"V2Score"`
					} `json:"nvd"`
				} `json:"CVSS"`
				PkgName          string `json:"PkgName"`
				InstalledVersion string `json:"InstalledVersion"`
				FixedVersion     string `json:"FixedVersion"`
				Description      string `json:"Description"`
			} `json:"Vulnerabilities"`
		} `json:"Results"`
	}

	if err := json.Unmarshal(data, &trivyReport); err != nil {
		return nil, fmt.Errorf("failed to parse JSON report: %w", err)
	}

	var vulnerabilities []Vulnerability
	for _, result := range trivyReport.Results {
		for _, vuln := range result.Vulnerabilities {
			v := Vulnerability{
				ID:           vuln.VulnerabilityID,
				Severity:     vuln.Severity,
				Package:      vuln.PkgName,
				Version:      vuln.InstalledVersion,
				FixedVersion: vuln.FixedVersion,
				Description:  vuln.Description,
			}

			// Get CVSS score
			if vuln.CVSS.NVD.V3Score != nil {
				v.CVSSScore = *vuln.CVSS.NVD.V3Score
			} else if vuln.CVSS.NVD.V2Score != nil {
				v.CVSSScore = *vuln.CVSS.NVD.V2Score
			}

			vulnerabilities = append(vulnerabilities, v)
		}
	}

	return vulnerabilities, nil
}

// summarizeVulnerabilities creates a summary of vulnerabilities by severity
func (s *TrivyScanner) summarizeVulnerabilities(vulns []Vulnerability) VulnerabilitySummary {
	summary := VulnerabilitySummary{}

	for _, vuln := range vulns {
		summary.Total++
		switch vuln.Severity {
		case "CRITICAL":
			summary.Critical++
		case "HIGH":
			summary.High++
		case "MEDIUM":
			summary.Medium++
		case "LOW":
			summary.Low++
		default:
			summary.Unknown++
		}
	}

	return summary
}

// updateDatabase updates the trivy vulnerability database
func (s *TrivyScanner) updateDatabase(ctx context.Context) error {
	s.logger.Info("Updating Trivy vulnerability database")

	cmd := exec.CommandContext(ctx, "trivy", "--cache-dir", s.config.Trivy.CacheDir, "image", "--download-db-only")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to update database: %w", err)
	}

	s.logger.Info("Database update completed")
	return nil
}

// startDBUpdateRoutine runs periodic database updates
func (s *TrivyScanner) startDBUpdateRoutine() {
	ticker := time.NewTicker(s.config.Trivy.UpdateInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
			if err := s.updateDatabase(ctx); err != nil {
				s.logger.Errorf("Scheduled database update failed: %v", err)
			}
			cancel()
		}
	}
}

// sendErrorResponse sends a standardized error response
func (s *TrivyScanner) sendErrorResponse(w http.ResponseWriter, code, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	errorResp := ScanError{
		Code:      code,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": false,
		"error":   errorResp,
	})
}

// ensureDirectories creates necessary directories
func ensureDirectories(config *Config) error {
	dirs := []string{
		config.Trivy.CacheDir,
		config.Trivy.ReportsDir,
	}

	for _, dir := range dirs {
		if err := exec.Command("mkdir", "-p", dir).Run(); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", dir, err)
		}
	}

	return nil
}
