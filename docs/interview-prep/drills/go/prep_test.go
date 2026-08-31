package prep

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestFetchAllPreservesOrderAndBoundsConcurrency(t *testing.T) {
	var inFlight, peak int64
	ids := []string{"a", "b", "c", "d", "e", "f"}
	got, err := FetchAll(context.Background(), ids, 2, func(ctx context.Context, id string) (string, error) {
		n := atomic.AddInt64(&inFlight, 1)
		for {
			p := atomic.LoadInt64(&peak)
			if n <= p || atomic.CompareAndSwapInt64(&peak, p, n) {
				break
			}
		}
		time.Sleep(5 * time.Millisecond)
		atomic.AddInt64(&inFlight, -1)
		return strings.ToUpper(id), nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Join(got, "") != "ABCDEF" {
		t.Fatalf("order not preserved: %v", got)
	}
	if peak > 2 {
		t.Fatalf("concurrency limit breached: peak=%d", peak)
	}
}

func TestFetchAllFailsFast(t *testing.T) {
	_, err := FetchAll(context.Background(), []string{"a", "b"}, 2, func(ctx context.Context, id string) (int, error) {
		if id == "a" {
			return 0, errors.New("boom")
		}
		<-ctx.Done()
		return 0, ctx.Err()
	})
	if err == nil || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("want boom, got %v", err)
	}
}

func TestRetryStopsOnPermanent(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 5, time.Millisecond, 10*time.Millisecond, func(ctx context.Context) error {
		calls++
		return &Permanent{errors.New("422")}
	})
	if calls != 1 || err == nil {
		t.Fatalf("calls=%d err=%v", calls, err)
	}
}

func TestRetryEventuallySucceeds(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 5, time.Millisecond, 5*time.Millisecond, func(ctx context.Context) error {
		calls++
		if calls < 3 {
			return errors.New("503")
		}
		return nil
	})
	if err != nil || calls != 3 {
		t.Fatalf("calls=%d err=%v", calls, err)
	}
}

func TestMapOrder(t *testing.T) {
	raw := []byte(`{"order_id":"A1","buyer":{"first_name":"Ada","last_name":"L","email_address":" ADA@X.COM "},
	  "line_items":[{"sku":"S1","quantity":2,"unit_price_cents":500}],"metadata":{},"placed_at":"2026-01-02T03:04:05Z"}`)
	d, err := MapOrder(raw, "vendor-x")
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if d.Email != "ada@x.com" || d.CustomerName != "Ada L" || d.TotalCents != 1000 {
		t.Fatalf("bad mapping: %+v", d)
	}
}

func TestMapOrderCollectsProblems(t *testing.T) {
	raw := []byte(`{"order_id":"","buyer":{"first_name":"A","last_name":"B","email_address":""},
	  "line_items":[{"sku":"S1","quantity":0,"unit_price_cents":500}],"metadata":{},"placed_at":"nope"}`)
	_, err := MapOrder(raw, "vendor-x")
	if err == nil || !strings.Contains(err.Error(), "missing order_id") || !strings.Contains(err.Error(), "bad placed_at") {
		t.Fatalf("want aggregated problems, got %v", err)
	}
}

func TestTokenBucket(t *testing.T) {
	now := time.Now()
	b := NewTokenBucket(10, 2)
	b.now = func() time.Time { return now }
	b.last = now
	if !b.Allow() || !b.Allow() {
		t.Fatal("burst should allow 2")
	}
	if b.Allow() {
		t.Fatal("third call should be denied")
	}
	now = now.Add(200 * time.Millisecond) // +2 tokens
	if !b.Allow() {
		t.Fatal("should refill")
	}
}

func TestWorkerPool(t *testing.T) {
	got := WorkerPool(context.Background(), []int{1, 2, 3, 4}, 3, func(n int) int { return n * n })
	want := []int{1, 4, 9, 16}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v want %v", got, want)
		}
	}
}

// --- handler test: the shape an interviewer likes to see ---

type fakeStore struct {
	id  string
	err error
}

func (f fakeStore) Create(ctx context.Context, r CreateOrderReq) (string, error) {
	return f.id, f.err
}

func TestHandleCreateOrder(t *testing.T) {
	tests := []struct {
		name       string
		body       string
		store      fakeStore
		wantStatus int
		wantCode   string
	}{
		{"created", `{"external_id":"A1","email":"a@x.com"}`, fakeStore{id: "o_1"}, 201, ""},
		{"bad json", `{`, fakeStore{}, 400, "invalid_json"},
		{"missing field", `{"external_id":"A1"}`, fakeStore{}, 422, "missing_field"},
		{"store failure", `{"external_id":"A1","email":"a@x.com"}`, fakeStore{err: errors.New("db down")}, 500, "internal"},
		{"expected failure", `{"external_id":"A1","email":"a@x.com"}`,
			fakeStore{err: &APIError{409, "duplicate", "already exists"}}, 409, "duplicate"},
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/orders", strings.NewReader(tt.body))
			rec := httptest.NewRecorder()
			HandleCreateOrder(tt.store, log).ServeHTTP(rec, req)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d (body %s)", rec.Code, tt.wantStatus, rec.Body)
			}
			if tt.wantCode != "" && !strings.Contains(rec.Body.String(), tt.wantCode) {
				t.Errorf("body = %s, want code %q", rec.Body, tt.wantCode)
			}
		})
	}
}
