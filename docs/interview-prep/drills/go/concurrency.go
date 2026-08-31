package prep

import (
	"context"
	"fmt"
	"sync"
)

// FetchAll runs fn over every id with at most `limit` in flight, preserves
// input order in the result, and fails fast on the first error.
func FetchAll[T any](ctx context.Context, ids []string, limit int, fn func(context.Context, string) (T, error)) ([]T, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	out := make([]T, len(ids))
	sem := make(chan struct{}, limit)
	var wg sync.WaitGroup
	var once sync.Once
	var firstErr error

	for i, id := range ids {
		wg.Add(1)
		go func(i int, id string) {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				return
			}
			defer func() { <-sem }()

			v, err := fn(ctx, id)
			if err != nil {
				once.Do(func() {
					firstErr = fmt.Errorf("id %s: %w", id, err)
					cancel()
				})
				return
			}
			out[i] = v // distinct index per goroutine: no lock needed
		}(i, id)
	}
	wg.Wait()
	return out, firstErr
}

// WorkerPool is the fixed-N variant: N goroutines draining one job channel.
func WorkerPool(ctx context.Context, jobs []int, workers int, do func(int) int) []int {
	in := make(chan int)
	type res struct{ idx, val int }
	outCh := make(chan res)

	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for idx := range in {
				select {
				case outCh <- res{idx, do(jobs[idx])}:
				case <-ctx.Done():
					return
				}
			}
		}()
	}
	go func() {
		defer close(in)
		for i := range jobs {
			select {
			case in <- i:
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() { wg.Wait(); close(outCh) }()

	out := make([]int, len(jobs))
	for r := range outCh {
		out[r.idx] = r.val
	}
	return out
}
