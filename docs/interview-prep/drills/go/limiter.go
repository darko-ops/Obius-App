package prep

import (
	"sync"
	"time"
)

// TokenBucket: `rate` tokens/sec, burst `capacity`. Lazily refills on Allow,
// so there is no background goroutine to leak.
type TokenBucket struct {
	mu       sync.Mutex
	tokens   float64
	capacity float64
	rate     float64
	last     time.Time
	now      func() time.Time // injectable for tests
}

func NewTokenBucket(rate, capacity float64) *TokenBucket {
	return &TokenBucket{tokens: capacity, capacity: capacity, rate: rate, now: time.Now, last: time.Now()}
}

func (b *TokenBucket) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := b.now()
	b.tokens += now.Sub(b.last).Seconds() * b.rate
	if b.tokens > b.capacity {
		b.tokens = b.capacity
	}
	b.last = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}
