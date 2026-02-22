# Obius Cloud Infrastructure Plan

**Author:** Chief Architect
**Date:** February 2026
**Status:** Decision Document
**Audience:** Founders, Engineering

---

## Executive Summary

Obius should **stay on Supabase**. Do not use iCloud/CloudKit. The current architecture
is the right one — it just needs proper tier planning and AI cost guardrails so the
economics work as you scale from beta to your first 1,000 paying users.

**Bottom line:** You can run Obius for **$0-15/month** through your first 500 users,
and **$25-75/month** through your first 5,000 users. The real cost driver isn't
infrastructure — it's AI API calls, and that's where the economic design matters most.

---

## Why NOT iCloud/CloudKit

This is the first question to put to rest.

| Factor | iCloud/CloudKit | Supabase (current) |
|--------|----------------|-------------------|
| Cost | $0 (included in Apple Developer $99/yr) | $0 free tier → $25/mo Pro |
| Cross-platform | Apple only, forever | iOS, Android, Web — any client |
| Custom backend logic | No server-side code | Edge Functions (Deno/TS) |
| AI pipeline | Not possible | Already built (embeddings, summaries) |
| Vector search (pgvector) | Not possible | Already working |
| Custom sync protocol | Must use Apple's opaque sync | You own the sync protocol |
| Auth flexibility | Apple ID only | Email, OAuth, magic link, SSO |
| Database control | Key-value store (limited queries) | Full PostgreSQL |
| Sharing (public links) | Very limited | Already built with RLS |
| Migration path | Locked to Apple forever | Standard Postgres — portable anywhere |

**Verdict:** iCloud would require you to **throw away** your entire backend — the sync
engine, AI pipeline, semantic search, sharing system, and auth. You'd get a free
key-value store that can't do any of the things that make Obius special. It's a
non-starter.

CloudKit makes sense for simple apps that just need iCloud document sync (like a
basic to-do list). Obius is well past that — you have a real backend with real
intelligence features. Keep it.

---

## The Right Architecture: What You Already Have

```
┌─────────────────────────────────────────────────────────┐
│                      iOS Client                          │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │   GRDB   │  │  SyncEngine  │  │  Supabase Swift   │  │
│  │ (SQLite) │  │ (push/pull)  │  │     SDK           │  │
│  └────┬─────┘  └──────┬───────┘  └────────┬──────────┘  │
│       │               │                   │              │
│   Local-first     Conflict             Auth +            │
│    storage       resolution          API calls           │
└───────────────────────┼───────────────────┼──────────────┘
                        │                   │
                        ▼                   ▼
┌───────────────────────────────────────────────────────────┐
│                    Supabase Cloud                          │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │  PostgreSQL   │  │    Auth      │  │    Storage     │  │
│  │  + pgvector   │  │  (GoTrue)   │  │  (S3-backed)   │  │
│  └──────┬───────┘  └──────────────┘  └────────────────┘  │
│         │                                                 │
│  ┌──────┴────────────────────────────────────────────┐   │
│  │              Edge Functions (Deno)                 │   │
│  │                                                    │   │
│  │  sync-pull     sync-push      generate-embedding   │   │
│  │  generate-summary   semantic-search                │   │
│  │  create-share  get-shared-content  add-comment     │   │
│  └────────────────────┬──────────────────────────────┘   │
│                       │                                   │
└───────────────────────┼───────────────────────────────────┘
                        │
              ┌─────────┼──────────┐
              ▼                    ▼
     ┌──────────────┐    ┌──────────────┐
     │   OpenAI API  │    │ Anthropic API │
     │  (embeddings) │    │  (summaries)  │
     └──────────────┘    └──────────────┘
```

This is a solid, modern architecture. Don't change it. Optimize it.

---

## Cost Breakdown by Growth Phase

### Phase 1: Beta → Launch (0-500 users) — Target: $0-15/mo

| Service | Tier | Monthly Cost | What You Get |
|---------|------|-------------|--------------|
| Supabase | Free | $0 | 500MB DB, 1GB storage, 50K MAU, 500K Edge Function invocations |
| Apple Developer | Annual | ~$8.25/mo ($99/yr) | App Store distribution |
| OpenAI API | Pay-as-you-go | ~$2-5 | Embeddings (text-embedding-3-small) |
| Anthropic API | Pay-as-you-go | ~$2-5 | Summaries (Claude Haiku) |
| Domain (obius.io) | Annual | ~$1/mo | Already have it |
| **Total** | | **~$13-19/mo** | |

**Key insight:** Supabase free tier is generous enough for your first 500 users. The
only real costs are AI API calls and your Apple Developer account.

### Phase 2: Growth (500-5,000 users) — Target: $25-75/mo

| Service | Tier | Monthly Cost | What You Get |
|---------|------|-------------|--------------|
| Supabase | Pro | $25 | 8GB DB, 100GB storage, unlimited MAU, daily backups |
| Apple Developer | Annual | ~$8.25/mo | Same |
| OpenAI API | Pay-as-you-go | ~$10-30 | Higher embedding volume |
| Anthropic API | Pay-as-you-go | ~$10-30 | Higher summary volume |
| **Total** | | **~$53-93/mo** | |

### Phase 3: Scale (5,000-50,000 users) — Target: $100-300/mo

At this point, subscription revenue should be covering costs. With even 2% conversion
at $4.99/mo:

- 50,000 users × 2% = 1,000 subscribers × $4.99 = **$4,990/mo revenue**
- Infrastructure at this scale: ~$200-500/mo
- **Margin: ~90%** — the economics work beautifully

---

## AI Cost Economics — The Critical Piece

This is where your business model either works or bleeds money. AI API calls are your
#1 variable cost, and they're also your #1 premium feature. This is actually perfect
for freemium.

### Cost Per Operation (current pricing)

| Operation | Model | Cost Per Call | Notes |
|-----------|-------|--------------|-------|
| Embedding (per section) | text-embedding-3-small | ~$0.00002 | 1536 dims, very cheap |
| Summary (per note) | Claude Haiku 4.5 | ~$0.001-0.003 | Depends on note length |
| Semantic search | text-embedding-3-small | ~$0.00002 | Query embedding only |

### Per-User Monthly AI Cost Estimates

| User Type | Sections/mo | Summaries/mo | Searches/mo | AI Cost/mo |
|-----------|-------------|-------------|-------------|------------|
| Light (free) | 50 | 5 | 10 | ~$0.02 |
| Medium (free) | 200 | 20 | 30 | ~$0.07 |
| Heavy (paid) | 500 | 50 | 100 | ~$0.17 |
| Power (paid) | 1,000 | 100 | 200 | ~$0.35 |

**The math works:** Even a power user costs you ~$0.35/mo in AI, against a $4.99/mo
subscription. That's a **93% margin** on AI costs alone.

### AI Cost Guardrails (Implement These)

1. **Free tier limits:**
   - 100 notes max (you already have `maxNotesForFreeUser = 100`)
   - Cap AI summaries to 10/day for free users
   - Cap semantic searches to 20/day for free users
   - No embeddings for free users (keyword search only)

2. **Smart batching:**
   - Don't regenerate embeddings on every keystroke — debounce to on-save
   - Batch embedding requests (OpenAI supports batch API at 50% discount)
   - Only regenerate summary when content materially changes (hash comparison)

3. **Model selection:**
   - Use `text-embedding-3-small` (not `ada-002`) — same quality, lower cost
   - Use Claude Haiku (not Sonnet/Opus) for summaries — fast, cheap, good enough
   - Consider on-device summarization with Apple Intelligence for free tier

---

## Freemium Feature Gates (Revenue Architecture)

This is how the cloud infrastructure maps to your business model:

```
┌─────────────────────────────────────────────────┐
│                 FREE TIER ($0)                    │
│                                                   │
│  ✓ Unlimited local notes (up to 100 synced)      │
│  ✓ Full offline functionality                     │
│  ✓ Basic keyword search                           │
│  ✓ Single-device (no sync)                        │
│  ✓ Basic sharing (view-only links)                │
│  ✓ Manual note titles                             │
│                                                   │
├─────────────────────────────────────────────────┤
│              OBIUS PRO ($4.99/mo)                 │
│                                                   │
│  ✓ Everything in Free                             │
│  ✓ Cloud sync across devices                      │
│  ✓ AI-powered semantic search                     │
│  ✓ AI auto-titles and summaries                   │
│  ✓ Unlimited synced notes                         │
│  ✓ Collaborative sharing (comments)               │
│  ✓ Priority support                               │
│                                                   │
└─────────────────────────────────────────────────┘
```

**Why this works economically:**
- Free users cost you **$0/mo** (local-only, no cloud, no AI)
- Only paying users trigger cloud sync and AI calls
- Your variable costs (AI) only scale with revenue

---

## Infrastructure Setup Checklist

### Immediate (Do Now)

- [ ] **Create Supabase production project** at supabase.com/dashboard
  - Region: Choose closest to your primary user base (likely `us-east-1` or `us-west-1`)
  - Start on Free tier — no credit card needed
- [ ] **Run database migrations** against production
  ```bash
  supabase link --project-ref YOUR_PROJECT_REF
  supabase db push
  ```
- [ ] **Deploy Edge Functions**
  ```bash
  supabase functions deploy
  ```
- [ ] **Set environment secrets** in Supabase Dashboard
  ```
  OPENAI_API_KEY=sk-...
  ANTHROPIC_API_KEY=sk-ant-...
  ```
- [ ] **Configure iOS app** with production Supabase URL/key
  - Update `Secrets.xcconfig` (never commit this file)
  - Verify `.gitignore` excludes it
- [ ] **Set up OpenAI billing alerts** at $10, $25, $50
- [ ] **Set up Anthropic billing alerts** at $10, $25, $50

### Before Launch

- [ ] **Enable Supabase email confirmations** in production
- [ ] **Configure custom SMTP** (so emails come from @obius.io, not @supabase.io)
  - Recommendation: Resend.com ($0 for first 3,000 emails/mo)
- [ ] **Set up Supabase database backups** (automatic on Pro, manual on Free)
- [ ] **Add rate limiting** to Edge Functions (prevent abuse)
- [ ] **Configure Apple App Store subscriptions** (StoreKit 2)
- [ ] **Add RevenueCat or roll your own** for subscription management
  - RevenueCat is free under $2.5K MTR — recommended for simplicity

### Post-Launch Monitoring

- [ ] **Supabase Dashboard** — monitor DB size, function invocations, auth users
- [ ] **OpenAI usage dashboard** — track embedding costs
- [ ] **Anthropic console** — track summary costs
- [ ] **Set up uptime monitoring** — UptimeRobot (free for 50 monitors)

---

## When to Upgrade: Decision Triggers

| Trigger | Action | Cost Change |
|---------|--------|-------------|
| Database > 400MB | Upgrade to Supabase Pro | +$25/mo |
| Edge Function invocations > 400K/mo | Upgrade to Supabase Pro | (included) |
| >50K monthly active users | Upgrade to Supabase Pro | (included) |
| Need daily backups | Upgrade to Supabase Pro | (included) |
| Need custom domain for API | Upgrade to Supabase Pro | (included) |
| AI costs > $50/mo | Implement batching, consider on-device models | -30-50% |
| >50,000 users | Evaluate Supabase Team plan ($599/mo) | Revenue should cover |

---

## Future Platform Expansion (When You're Ready)

Since you're undecided on platforms, here's why the current stack keeps all doors open:

### Adding a Web Client
- Supabase has official JS/TS SDK (`@supabase/supabase-js`)
- Your Edge Functions are already HTTP endpoints — any client can call them
- Auth works out of the box (email/password, OAuth)
- Build with Next.js or SvelteKit, deploy on Vercel (free tier)
- **Effort:** 2-4 weeks for MVP web client
- **Additional cost:** $0 (Vercel free tier)

### Adding Android
- Supabase has official Kotlin SDK (`supabase-kt`)
- Same Edge Functions, same auth, same sync protocol
- Your sync protocol is JSON over HTTP — platform agnostic
- **Effort:** 4-8 weeks (rebuild UI, reuse protocol)
- **Additional cost:** $25/yr Google Play Developer account

### Adding Desktop (macOS)
- Share code with iOS via SwiftUI + Catalyst or native macOS target
- Same Supabase backend — no changes needed
- **Effort:** 2-4 weeks (UI adaptation)
- **Additional cost:** $0 (same Apple Developer account)

**If you'd chosen iCloud, none of this would be possible.** The Supabase architecture
is the foundation for a multi-platform product.

---

## Architecture Decisions Record

### ADR-001: Supabase over iCloud
- **Decision:** Use Supabase as cloud backend
- **Rationale:** AI features, cross-platform potential, custom sync, full SQL
- **Trade-off:** Small monthly cost vs. iCloud's $0, but enables the product vision

### ADR-002: AI as Premium Feature Gate
- **Decision:** AI features (semantic search, auto-summaries) are Pro-only
- **Rationale:** Aligns variable costs (AI API) with revenue (subscriptions)
- **Trade-off:** Free users get less magic, but the economics are sustainable

### ADR-003: Local-First Architecture
- **Decision:** All data lives locally first, cloud is optional sync
- **Rationale:** Best UX (instant, offline), reduces server load, privacy-respecting
- **Trade-off:** More complex sync logic, but already built

### ADR-004: Edge Functions over Traditional Server
- **Decision:** Use Supabase Edge Functions (Deno) instead of a separate API server
- **Rationale:** Zero infrastructure to manage, scales automatically, co-located with DB
- **Trade-off:** Deno runtime limitations, but sufficient for current needs

---

## Summary

| Question | Answer |
|----------|--------|
| Use iCloud? | **No.** It would kill your AI features and cross-platform future. |
| Use Supabase? | **Yes.** You already have a working backend. Ship it. |
| Monthly cost (Year 1)? | **$0-25/mo** for infrastructure + **$5-30/mo** for AI APIs |
| When does it pay for itself? | **~100 subscribers** at $4.99/mo covers all costs |
| Biggest cost risk? | **AI API calls** — gate them behind Pro subscription |
| What if you need to leave Supabase? | Standard Postgres — migrate to any cloud provider |

**The architecture is done. The infrastructure is ready. Focus on shipping the app,
not rebuilding the backend.**
