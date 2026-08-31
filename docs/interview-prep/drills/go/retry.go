package prep

import (
	"context"
	"errors"
	"math/rand"
	"time"
)

// Permanent marks an error that must not be retried (4xx, validation, etc.).
type Permanent struct{ Err error }

func (p *Permanent) Error() string { return p.Err.Error() }
func (p *Permanent) Unwrap() error { return p.Err }

// Retry calls fn with exponential backoff + full jitter, capped, and always
// respects ctx cancellation (including while sleeping).
func Retry(ctx context.Context, attempts int, base, max time.Duration, fn func(context.Context) error) error {
	var err error
	for i := 0; i < attempts; i++ {
		if err = fn(ctx); err == nil {
			return nil
		}
		var perm *Permanent
		if errors.As(err, &perm) {
			return err // don't burn retries on a request that can never succeed
		}
		if i == attempts-1 {
			break
		}
		backoff := base << i
		if backoff > max {
			backoff = max
		}
		sleep := time.Duration(rand.Int63n(int64(backoff) + 1)) // full jitter
		t := time.NewTimer(sleep)
		select {
		case <-ctx.Done():
			t.Stop()
			return ctx.Err()
		case <-t.C:
		}
	}
	return err
}
