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

	"container-security-mts/internal/scanner"
	"container-security-mts/pkg/utils"
)

func main() {
	var (
		port     = flag.String("port", "8080", "Port to listen on")
		host     = flag.String("host", "0.0.0.0", "Host to bind to")
		logLevel = flag.String("log-level", "info", "Log level (debug, info, warn, error)")
		config   = flag.String("config", "/opt/trivy/config.yaml", "Configuration file path")
	)
	flag.Parse()

	// Initialize logger
	logger := utils.NewLogger(*logLevel)
	defer logger.Sync()

	// Load configuration
	cfg, err := scanner.LoadConfig(*config)
	if err != nil {
		logger.Warnf("Failed to load config from %s: %v, using defaults", *config, err)
		cfg = scanner.DefaultConfig()
	}

	// Initialize scanner
	trivyScanner, err := scanner.NewTrivyScanner(cfg, logger)
	if err != nil {
		logger.Fatalf("Failed to initialize Trivy scanner: %v", err)
	}

	// Initialize HTTP server
	addr := fmt.Sprintf("%s:%s", *host, *port)
	server := &http.Server{
		Addr:         addr,
		Handler:      setupRoutes(trivyScanner, logger),
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
		IdleTimeout:  cfg.Server.IdleTimeout,
	}

	// Start server in goroutine
	go func() {
		logger.Infof("Starting Trivy Scanner service on %s", addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	logger.Info("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logger.Errorf("Server forced to shutdown: %v", err)
	}

	logger.Info("Server exited")
}

func setupRoutes(scanner *scanner.TrivyScanner, logger *utils.Logger) http.Handler {
	mux := http.NewServeMux()

	// Health check endpoint
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":    "healthy",
			"service":   "trivy-scanner",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	// Readiness check endpoint
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		if err := scanner.HealthCheck(); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":  "not ready",
				"error":   err.Error(),
				"service": "trivy-scanner",
			})
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":    "ready",
			"service":   "trivy-scanner",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	// API v1 routes
	v1 := http.NewServeMux()
	v1.HandleFunc("/scan", scanner.ScanHandler)

	// Mount v1 API
	mux.Handle("/api/v1/", http.StripPrefix("/api/v1", v1))

	// Add logging middleware
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
