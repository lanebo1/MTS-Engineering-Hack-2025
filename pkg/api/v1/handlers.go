package v1

import (
	"encoding/json"
	"net/http"
	"time"

	"container-security-mts/internal/opa"
	"container-security-mts/internal/scanner"
	"container-security-mts/pkg/utils"
)

// Handler combines all API handlers
type Handler struct {
	trivyScanner *scanner.TrivyScanner
	opaEvaluator *opa.OPAEvaluator
	logger       *utils.Logger
}

// NewHandler creates a new API handler
func NewHandler(trivyScanner *scanner.TrivyScanner, opaEvaluator *opa.OPAEvaluator, logger *utils.Logger) *Handler {
	return &Handler{
		trivyScanner: trivyScanner,
		opaEvaluator: opaEvaluator,
		logger:       logger,
	}
}

// SetupRoutes sets up all API routes
func (h *Handler) SetupRoutes() http.Handler {
	mux := http.NewServeMux()

	// Scan endpoints
	mux.HandleFunc("/api/v1/scan", h.trivyScanner.ScanHandler)

	// Policy endpoints
	mux.HandleFunc("/policies/evaluate", h.opaEvaluator.EvaluatePolicyHandler)
	mux.HandleFunc("/policies/update", h.PolicyUpdateHandler)
	mux.HandleFunc("/policies/health", h.PolicyHealthHandler)

	return mux
}

// sendErrorResponse sends a standardized error response
func (h *Handler) sendErrorResponse(w http.ResponseWriter, code, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	errorResp := ErrorResponse{
		Code:      code,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"error": errorResp,
	})
}
