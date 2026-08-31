package prep

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
)

// APIError is an expected failure with a stable, machine-readable code.
// Unexpected failures never become an APIError — they get logged and
// returned as a generic 500, so internals don't leak into responses.
type APIError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *APIError) Error() string { return e.Code + ": " + e.Message }

type CreateOrderReq struct {
	ExternalID string `json:"external_id"`
	Email      string `json:"email"`
}

type Store interface {
	Create(ctx context.Context, r CreateOrderReq) (string, error)
}

func HandleCreateOrder(store Store, log *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		var req CreateOrderReq
		body := http.MaxBytesReader(w, r.Body, 1<<20) // an unbounded body is a DoS
		if err := json.NewDecoder(body).Decode(&req); err != nil {
			writeErr(w, &APIError{http.StatusBadRequest, "invalid_json", "body is not valid JSON"})
			return
		}
		if req.ExternalID == "" || req.Email == "" {
			writeErr(w, &APIError{http.StatusUnprocessableEntity, "missing_field", "external_id and email are required"})
			return
		}

		id, err := store.Create(ctx, req)
		if err != nil {
			var apiErr *APIError
			if errors.As(err, &apiErr) {
				writeErr(w, apiErr)
				return
			}
			log.ErrorContext(ctx, "create order failed", "err", err, "external_id", req.ExternalID)
			writeErr(w, &APIError{http.StatusInternalServerError, "internal", "unexpected error"})
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(map[string]string{"id": id})
	}
}

func writeErr(w http.ResponseWriter, e *APIError) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(e.Status)
	_ = json.NewEncoder(w).Encode(e)
}
