# Full-stack technical screen prep

Preparation material for a 60-minute live-coding screen for a full-stack role
built on **Go, TypeScript, React, and third-party integrations** (2–4 years).

## Contents

| Path | What it is |
|------|------------|
| `screen-prep.html` | The guide: predicted questions with worked answers, covering the read on the job description, how to drive the hour, Go, TypeScript/async, React, REST/gRPC, data mapping, debugging, observability, behavioral, and a drill list. Open it in a browser. |
| `drills/go/` | A runnable Go module with every Go snippet from the guide, plus tests. |
| `drills/ts/` | The TypeScript async helpers from the guide. |

## Running the drills

```bash
cd drills/go
go vet ./... && go test -race ./...

cd ../ts
npx tsc --noEmit --strict --target es2022 --lib es2022,dom pool.ts paginate.ts
```

## What's in the Go drills

| File | Problem |
|------|---------|
| `concurrency.go` | Bounded-concurrency fetch that preserves input order and fails fast; fixed-N worker pool over a job channel. |
| `retry.go` | Exponential backoff with full jitter, a `Permanent` error type that stops retries, and cancellation honoured while sleeping. |
| `limiter.go` | Token-bucket rate limiter with lazy refill and an injectable clock, so tests don't sleep. |
| `mapper.go` | Vendor payload → internal record, aggregating every problem instead of bailing on the first. |
| `http.go` | HTTP handler: bounded body, validation, typed errors mapped to status codes. |
| `prep_test.go` | Table-driven tests, including a concurrency-limit assertion and `httptest` handler tests. |

The point of the drills is to **type them from an empty file**, not to read them.
