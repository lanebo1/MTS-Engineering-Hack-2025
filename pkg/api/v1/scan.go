package v1

import "time"

// ScanRequest represents a request to scan a container image
type ScanRequest struct {
	Image          string   `json:"image" validate:"required"`
	ScanTypes      []string `json:"scan_types,omitempty"`
	SeverityLevels []string `json:"severity_levels,omitempty"`
	Format         string   `json:"format,omitempty"`
	SkipDBUpdate   bool     `json:"skip_db_update,omitempty"`
}

// ScanResponse represents the response from a scan operation
type ScanResponse struct {
	Success         bool                 `json:"success"`
	Image           string               `json:"image"`
	ScanTime        string               `json:"scan_time"`
	StartTime       string               `json:"start_time,omitempty"`
	Vulnerabilities []Vulnerability      `json:"vulnerabilities"`
	Summary         VulnerabilitySummary `json:"summary"`
	ReportFile      string               `json:"report_file,omitempty"`
	Error           *ErrorResponse       `json:"error,omitempty"`
}

// Vulnerability represents a security vulnerability
type Vulnerability struct {
	ID           string  `json:"id" example:"CVE-2023-12345"`
	Severity     string  `json:"severity" example:"CRITICAL"`
	CVSSScore    float64 `json:"cvss_score" example:"9.8"`
	Package      string  `json:"package" example:"openssl"`
	Version      string  `json:"version" example:"1.1.1"`
	FixedVersion string  `json:"fixed_version,omitempty" example:"1.1.1u"`
	Description  string  `json:"description" example:"Buffer overflow vulnerability"`
}

// VulnerabilitySummary provides counts of vulnerabilities by severity
type VulnerabilitySummary struct {
	Total    int `json:"total" example:"15"`
	Critical int `json:"critical" example:"2"`
	High     int `json:"high" example:"5"`
	Medium   int `json:"medium" example:"8"`
	Low      int `json:"low" example:"0"`
	Unknown  int `json:"unknown" example:"0"`
}

// ErrorResponse represents an error response
type ErrorResponse struct {
	Code      string                 `json:"code" example:"SCAN_FAILED"`
	Message   string                 `json:"message" example:"Failed to scan image: connection timeout"`
	Details   map[string]interface{} `json:"details,omitempty"`
	Timestamp string                 `json:"timestamp" example:"2024-01-01T12:00:00Z"`
}

// HealthResponse represents a health check response
type HealthResponse struct {
	Status    string `json:"status" example:"healthy"`
	Service   string `json:"service" example:"trivy-scanner"`
	Timestamp string `json:"timestamp" example:"2024-01-01T12:00:00Z"`
	Version   string `json:"version,omitempty" example:"1.0.0"`
}

// MetricsResponse represents metrics data
type MetricsResponse struct {
	TotalScans           int64   `json:"total_scans" example:"150"`
	SuccessfulScans      int64   `json:"successful_scans" example:"145"`
	FailedScans          int64   `json:"failed_scans" example:"5"`
	AverageScanTime      float64 `json:"average_scan_time_seconds" example:"45.2"`
	LastDBUpdate         string  `json:"last_db_update" example:"2024-01-01T12:00:00Z"`
	VulnerabilitiesFound int64   `json:"vulnerabilities_found" example:"234"`
}

// ScanStatus represents the status of a scan operation
type ScanStatus struct {
	ID        string     `json:"id" example:"scan_12345"`
	Status    string     `json:"status" example:"running"` // running, completed, failed
	Image     string     `json:"image" example:"nginx:1.21"`
	StartTime time.Time  `json:"start_time"`
	EndTime   *time.Time `json:"end_time,omitempty"`
	Progress  float64    `json:"progress" example:"0.75"` // 0.0 to 1.0
	Error     string     `json:"error,omitempty"`
}

// BatchScanRequest represents a request to scan multiple images
type BatchScanRequest struct {
	Images         []string `json:"images" validate:"required,min=1,max=10"`
	ScanTypes      []string `json:"scan_types,omitempty"`
	SeverityLevels []string `json:"severity_levels,omitempty"`
	Format         string   `json:"format,omitempty"`
	Concurrent     bool     `json:"concurrent,omitempty"` // Run scans concurrently
	MaxConcurrency int      `json:"max_concurrency,omitempty"`
}

// BatchScanResponse represents the response from a batch scan operation
type BatchScanResponse struct {
	TotalImages    int            `json:"total_images"`
	CompletedScans int            `json:"completed_scans"`
	FailedScans    int            `json:"failed_scans"`
	Results        []ScanResponse `json:"results"`
	Summary        BatchSummary   `json:"summary"`
	StartTime      string         `json:"start_time"`
	EndTime        string         `json:"end_time"`
}

// BatchSummary provides summary statistics for batch operations
type BatchSummary struct {
	TotalVulnerabilities int     `json:"total_vulnerabilities"`
	ImagesWithCritical   int     `json:"images_with_critical"`
	ImagesWithHigh       int     `json:"images_with_high"`
	AverageScanTime      float64 `json:"average_scan_time_seconds"`
}
