package v1

import (
	"encoding/json"
	"net/http"

	"container-security-mts/internal/opa"
)

// PolicyUpdateHandler handles policy update requests
func (h *Handler) PolicyUpdateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req opa.PolicyUpdateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.Errorf("Failed to decode policy update request: %v", err)
		h.sendErrorResponse(w, "INVALID_REQUEST", "Failed to decode request body", http.StatusBadRequest)
		return
	}

	// Validate request
	if req.PolicyName == "" {
		h.sendErrorResponse(w, "INVALID_REQUEST", "Policy name is required", http.StatusBadRequest)
		return
	}

	if req.PolicyData == "" {
		h.sendErrorResponse(w, "INVALID_REQUEST", "Policy data is required", http.StatusBadRequest)
		return
	}

	// Update policy
	if err := h.opaEvaluator.UpdatePolicy(r.Context(), &req); err != nil {
		h.logger.Errorf("Policy update failed: %v", err)
		h.sendErrorResponse(w, "UPDATE_FAILED", err.Error(), http.StatusInternalServerError)
		return
	}

	// Send success response
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Policy updated successfully",
		"policy":  req.PolicyName,
	})
}

// PolicyHealthHandler handles OPA health check requests
func (h *Handler) PolicyHealthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := h.opaEvaluator.HealthCheck(); err != nil {
		h.logger.Errorf("OPA health check failed: %v", err)
		h.sendErrorResponse(w, "HEALTH_CHECK_FAILED", err.Error(), http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "healthy",
		"service": "opa",
	})
}
