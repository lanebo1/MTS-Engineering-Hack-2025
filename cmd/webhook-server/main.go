package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"container-security-mts/internal/cosign"
	"container-security-mts/internal/notifications"
	"container-security-mts/internal/opa"
	"container-security-mts/internal/scanner"
	v1 "container-security-mts/pkg/api/v1"
	"container-security-mts/pkg/utils"
)

func main() {
	var (
		metricsPort    = flag.String("metrics-port", "8081", "HTTP port for metrics and health checks")
		host           = flag.String("host", "0.0.0.0", "Host to bind to")
		logLevel       = flag.String("log-level", "info", "Log level (debug, info, warn, error)")
		telegramToken  = flag.String("telegram-token", "", "Telegram bot token for notifications")
		telegramChatID = flag.String("telegram-chat-id", "", "Telegram chat ID for notifications")
	)
	flag.Parse()

	// Initialize logger
	logger := utils.NewLogger(*logLevel)
	defer logger.Sync()

	logger.Infof("Starting Container Security Webhook Server")

	// Load webhook configuration
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")
	tlsEnabled := certFile != "" && keyFile != ""

	config := &v1.WebhookConfig{
		Port:           8443,
		Host:           *host,
		TLSEnabled:     tlsEnabled,
		CertFile:       certFile,
		KeyFile:        keyFile,
		ReadTimeout:    30 * time.Second,
		WriteTimeout:   30 * time.Second,
		IdleTimeout:    60 * time.Second,
		MaxRequestSize: 10 * 1024 * 1024, // 10MB
		ValidationMode: "strict",
	}

	// Initialize metrics
	metrics := utils.NewMetrics()

	// Initialize Trivy scanner (disabled for demo - trivy pods have image issues)
	logger.Warnf("Trivy scanner disabled for demo purposes (image pull issues)")
	realTrivyScanner := (*scanner.TrivyScanner)(nil)

	// Initialize Cosign verifier
	cosignConfig := cosign.DefaultConfig()
	cosignVerifier, err := cosign.NewCosignVerifier(cosignConfig, logger)
	if err != nil {
		logger.Fatalf("Failed to initialize Cosign verifier: %v", err)
	}

	// Initialize OPA evaluator with local policies
	opaConfig := opa.DefaultConfig()
	opaConfig.OPA.URL = "" // Use local policy evaluation instead of external server
	opaConfig.OPA.PoliciesPath = "/opt/webhook/policies"
	opaConfig.OPA.DataPath = "/opt/webhook/data"
	realOpaEvaluator, err := opa.NewOPAEvaluator(opaConfig, logger)
	if err != nil {
		logger.Fatalf("Failed to initialize OPA evaluator: %v", err)
	}

	// Initialize notifications
	telegramConfig := &notifications.Config{
		Enabled:  *telegramToken != "" && *telegramChatID != "",
		BotToken: *telegramToken,
		ChatID:   *telegramChatID,
	}
	notifier := notifications.NewNotifier(telegramConfig, logger)

	// Create webhook handler
	webhookHandler := v1.NewWebhookHandler(realTrivyScanner, cosignVerifier, realOpaEvaluator, logger, config, metrics, notifier)

	// Setup HTTP/HTTPS server for webhook endpoint
	portStr := fmt.Sprintf("%d", config.Port)
	logger.Infof("Webhook config: TLS=%v, Port=%s, Host=%s", config.TLSEnabled, portStr, config.Host)
	var webhookServer *http.Server
	if config.TLSEnabled && config.CertFile != "" && config.KeyFile != "" {
		// HTTPS server
		webhookServer = &http.Server{
			Addr:         fmt.Sprintf("%s:%s", config.Host, portStr),
			Handler:      setupWebhookRoutes(webhookHandler, logger),
			ReadTimeout:  config.ReadTimeout,
			WriteTimeout: config.WriteTimeout,
			IdleTimeout:  config.IdleTimeout,
		}
	} else {
		// HTTP server (demo mode)
		webhookServer = &http.Server{
			Addr:         fmt.Sprintf("%s:%s", config.Host, portStr),
			Handler:      setupWebhookRoutes(webhookHandler, logger),
			ReadTimeout:  config.ReadTimeout,
			WriteTimeout: config.WriteTimeout,
			IdleTimeout:  config.IdleTimeout,
		}
	}

	// Setup HTTP server for metrics only
	metricsServer := &http.Server{
		Addr:         fmt.Sprintf("%s:%s", *host, *metricsPort),
		Handler:      setupMetricsRoutes(webhookHandler, metrics.Handler(), logger),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start webhook server in goroutine
	go func() {
		logger.Infof("Server address: %s, TLS enabled: %v", webhookServer.Addr, config.TLSEnabled)
		if config.TLSEnabled && config.CertFile != "" && config.KeyFile != "" {
			logger.Infof("Starting HTTPS webhook server on %s", webhookServer.Addr)
			if err := webhookServer.ListenAndServeTLS(config.CertFile, config.KeyFile); err != nil && err != http.ErrServerClosed {
				logger.Fatalf("Failed to start webhook server: %v", err)
			}
		} else {
			logger.Infof("Starting HTTP webhook server on %s", webhookServer.Addr)
			if err := webhookServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logger.Fatalf("Failed to start webhook server: %v", err)
			}
		}
	}()

	// Start metrics server in goroutine
	go func() {
		logger.Infof("Starting HTTP metrics server on %s", metricsServer.Addr)
		if err := metricsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatalf("Failed to start metrics server: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down servers...")

	// Graceful shutdown webhook server
	webhookCtx, webhookCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer webhookCancel()
	if err := webhookServer.Shutdown(webhookCtx); err != nil {
		logger.Errorf("Webhook server forced to shutdown: %v", err)
	}

	// Graceful shutdown metrics server
	metricsCtx, metricsCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer metricsCancel()
	if err := metricsServer.Shutdown(metricsCtx); err != nil {
		logger.Errorf("Metrics server forced to shutdown: %v", err)
	}

	logger.Info("Servers exited")
}

func setupWebhookRoutes(handler *v1.WebhookHandler, logger *utils.Logger) http.Handler {
	mux := http.NewServeMux()

	// Admission webhook endpoint
	mux.HandleFunc("/admission", handler.HandleAdmission)

	// Readiness probe
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":    "ready",
			"service":   "admission-webhook",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	return loggingMiddleware(mux, logger)
}

func setupMetricsRoutes(handler *v1.WebhookHandler, metricsHandler http.Handler, logger *utils.Logger) http.Handler {
	mux := http.NewServeMux()

	// Health check endpoint
	mux.HandleFunc("/health", handler.HealthCheckHandler)

	// Readiness probe endpoint
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":    "ready",
			"service":   "admission-webhook",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	// Metrics endpoint
	mux.Handle("/metrics", metricsHandler)

	return loggingMiddleware(mux, logger)
}

func loggingMiddleware(next http.Handler, logger *utils.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Create a response writer wrapper to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(wrapped, r)

		logger.Infof("%s %s %d %v",
			r.Method,
			r.URL.Path,
			wrapped.statusCode,
			time.Since(start),
		)
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
