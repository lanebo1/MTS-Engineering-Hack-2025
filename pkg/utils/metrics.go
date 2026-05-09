package utils

import (
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics holds Prometheus metrics
type Metrics struct {
	TotalScans           prometheus.Counter
	SuccessfulScans      prometheus.Counter
	FailedScans          prometheus.Counter
	ScanDuration         prometheus.Histogram
	VulnerabilitiesFound prometheus.Histogram
	DBUpdates            prometheus.Counter
	LastDBUpdate         prometheus.Gauge

	// Admission webhook metrics
	AdmissionRequestsTotal    prometheus.Counter
	AdmissionRequestsAllowed  prometheus.Counter
	AdmissionRequestsDenied   prometheus.Counter
	AdmissionRequestDuration  prometheus.Histogram
	AdmissionRequestsByReason *prometheus.CounterVec
	AdmissionRequestsByPod    *prometheus.CounterVec
}

// NewMetrics creates a new metrics instance
func NewMetrics() *Metrics {
	m := &Metrics{
		TotalScans: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_scans_total",
			Help: "Total number of container scans performed",
		}),
		SuccessfulScans: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_scans_successful_total",
			Help: "Total number of successful container scans",
		}),
		FailedScans: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_scans_failed_total",
			Help: "Total number of failed container scans",
		}),
		ScanDuration: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name:    "container_security_scan_duration_seconds",
			Help:    "Time taken to perform container scans",
			Buckets: prometheus.DefBuckets,
		}),
		VulnerabilitiesFound: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name:    "container_security_vulnerabilities_found",
			Help:    "Number of vulnerabilities found in scans",
			Buckets: []float64{0, 1, 5, 10, 25, 50, 100, 250, 500, 1000},
		}),
		DBUpdates: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_db_updates_total",
			Help: "Total number of database updates performed",
		}),
		LastDBUpdate: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "container_security_last_db_update_timestamp",
			Help: "Timestamp of the last database update",
		}),
		AdmissionRequestsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_admission_requests_total",
			Help: "Total number of admission webhook requests",
		}),
		AdmissionRequestsAllowed: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_admission_requests_allowed_total",
			Help: "Total number of admission requests allowed",
		}),
		AdmissionRequestsDenied: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "container_security_admission_requests_denied_total",
			Help: "Total number of admission requests denied",
		}),
		AdmissionRequestDuration: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name:    "container_security_admission_request_duration_seconds",
			Help:    "Time taken to process admission requests",
			Buckets: prometheus.DefBuckets,
		}),
		AdmissionRequestsByReason: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "container_security_admission_requests_by_reason_total",
			Help: "Admission requests by denial reason",
		}, []string{"reason", "severity"}),
		AdmissionRequestsByPod: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "container_security_admission_requests_by_pod_total",
			Help: "Admission requests by pod namespace and name",
		}, []string{"namespace", "pod_name", "allowed"}),
	}

	// Register metrics
	prometheus.MustRegister(
		m.TotalScans,
		m.SuccessfulScans,
		m.FailedScans,
		m.ScanDuration,
		m.VulnerabilitiesFound,
		m.DBUpdates,
		m.LastDBUpdate,
		m.AdmissionRequestsTotal,
		m.AdmissionRequestsAllowed,
		m.AdmissionRequestsDenied,
		m.AdmissionRequestDuration,
		m.AdmissionRequestsByReason,
		m.AdmissionRequestsByPod,
	)

	return m
}

// RecordScan records a scan operation
func (m *Metrics) RecordScan(success bool, duration time.Duration, vulnCount int) {
	m.TotalScans.Inc()
	m.ScanDuration.Observe(duration.Seconds())
	m.VulnerabilitiesFound.Observe(float64(vulnCount))

	if success {
		m.SuccessfulScans.Inc()
	} else {
		m.FailedScans.Inc()
	}
}

// RecordDBUpdate records a database update
func (m *Metrics) RecordDBUpdate() {
	m.DBUpdates.Inc()
	m.LastDBUpdate.SetToCurrentTime()
}

// RecordAdmissionRequest records an admission webhook request
func (m *Metrics) RecordAdmissionRequest(allowed bool, duration time.Duration, namespace, podName string, violations []string, severity string) {
	m.AdmissionRequestsTotal.Inc()
	m.AdmissionRequestDuration.Observe(duration.Seconds())

	if allowed {
		m.AdmissionRequestsAllowed.Inc()
		m.AdmissionRequestsByPod.WithLabelValues(namespace, podName, "true").Inc()
	} else {
		m.AdmissionRequestsDenied.Inc()
		m.AdmissionRequestsByPod.WithLabelValues(namespace, podName, "false").Inc()

		// Record denial reasons
		if len(violations) > 0 {
			reason := violations[0] // Use first violation as primary reason
			if len(reason) > 100 {  // Truncate long reasons
				reason = reason[:100] + "..."
			}
			m.AdmissionRequestsByReason.WithLabelValues(reason, severity).Inc()
		}
	}
}

// Handler returns an HTTP handler for metrics endpoint
func (m *Metrics) Handler() http.Handler {
	return promhttp.Handler()
}

// Middleware creates HTTP middleware for recording metrics
func (m *Metrics) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Create response writer wrapper to capture status
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(rw, r)

		// Record metrics for API calls
		// Note: For detailed per-request metrics, you'd need to track them in the handlers
		_ = time.Since(start) // duration calculated but not currently used
	})
}

// responseWriter wraps http.ResponseWriter to capture status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// GetStatusCode returns the captured status code
func (rw *responseWriter) GetStatusCode() int {
	return rw.statusCode
}

// PrometheusMetricsServer serves Prometheus metrics
type PrometheusMetricsServer struct {
	server *http.Server
}

// NewPrometheusMetricsServer creates a new metrics server
func NewPrometheusMetricsServer(addr string) *PrometheusMetricsServer {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())

	return &PrometheusMetricsServer{
		server: &http.Server{
			Addr:    addr,
			Handler: mux,
		},
	}
}

// Start starts the metrics server
func (p *PrometheusMetricsServer) Start() error {
	return p.server.ListenAndServe()
}

// Stop stops the metrics server
func (p *PrometheusMetricsServer) Stop() error {
	return p.server.Close()
}
