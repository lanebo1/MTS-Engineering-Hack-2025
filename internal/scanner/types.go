package scanner

import "time"

// ScanOptions defines options for a scan operation
type ScanOptions struct {
	ScanTypes      []string      `json:"scan_types"`
	SeverityLevels []string      `json:"severity_levels"`
	Format         string        `json:"format"`
	Timeout        time.Duration `json:"timeout"`
	SkipDBUpdate   bool          `json:"skip_db_update"`
}

// HealthStatus represents the health status of the scanner
type HealthStatus struct {
	Status    string    `json:"status"`
	Service   string    `json:"service"`
	Timestamp time.Time `json:"timestamp"`
	Version   string    `json:"version,omitempty"`
	Error     string    `json:"error,omitempty"`
}

// Metrics represents scanner metrics
type Metrics struct {
	TotalScans           int64     `json:"total_scans"`
	SuccessfulScans      int64     `json:"successful_scans"`
	FailedScans          int64     `json:"failed_scans"`
	AverageScanTime      float64   `json:"average_scan_time_seconds"`
	LastDBUpdate         time.Time `json:"last_db_update"`
	VulnerabilitiesFound int64     `json:"vulnerabilities_found"`
}

// ScanStats represents statistics for a single scan
type ScanStats struct {
	ImageName          string        `json:"image_name"`
	ScanDuration       time.Duration `json:"scan_duration"`
	VulnerabilityCount int           `json:"vulnerability_count"`
	CriticalCount      int           `json:"critical_count"`
	HighCount          int           `json:"high_count"`
	MediumCount        int           `json:"medium_count"`
	LowCount           int           `json:"low_count"`
	ScanTime           time.Time     `json:"scan_time"`
}

// TrivyReport represents the raw Trivy JSON report structure
type TrivyReport struct {
	SchemaVersion int           `json:"SchemaVersion"`
	ArtifactName  string        `json:"ArtifactName"`
	ArtifactType  string        `json:"ArtifactType"`
	CreatedAt     time.Time     `json:"CreatedAt"`
	Results       []TrivyResult `json:"Results"`
}

// TrivyResult represents a single result from Trivy scan
type TrivyResult struct {
	Target          string               `json:"Target"`
	Class           string               `json:"Class"`
	Type            string               `json:"Type"`
	Vulnerabilities []TrivyVulnerability `json:"Vulnerabilities"`
}

// TrivyVulnerability represents a single vulnerability from Trivy
type TrivyVulnerability struct {
	VulnerabilityID  string    `json:"VulnerabilityID"`
	PkgName          string    `json:"PkgName"`
	PkgPath          string    `json:"PkgPath,omitempty"`
	InstalledVersion string    `json:"InstalledVersion"`
	FixedVersion     string    `json:"FixedVersion,omitempty"`
	Severity         string    `json:"Severity"`
	Description      string    `json:"Description"`
	References       []string  `json:"References,omitempty"`
	CVSS             TrivyCVSS `json:"CVSS,omitempty"`
}

// TrivyCVSS represents CVSS scores from Trivy
type TrivyCVSS struct {
	NVD    TrivyCVSSSource `json:"nvd,omitempty"`
	RedHat TrivyCVSSSource `json:"redhat,omitempty"`
	GHSA   TrivyCVSSSource `json:"ghsa,omitempty"`
}

// TrivyCVSSSource represents a CVSS score source
type TrivyCVSSSource struct {
	V2Score  *float64 `json:"V2Score,omitempty"`
	V3Score  *float64 `json:"V3Score,omitempty"`
	V2Vector string   `json:"V2Vector,omitempty"`
	V3Vector string   `json:"V3Vector,omitempty"`
}
