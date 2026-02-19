# Obius: Stress Test, Target Segment & Positioning

## Part 1 — What Could Kill This

### Kill Shot 1: "Good Enough" Defaults

Apple Notes ships on a billion devices. It is free, fast, syncs via iCloud, and gets better every year. Google Keep is the same on Android. The average user who downloads Obius will compare their first 30 seconds in the app to a tool they already know and trust.

**The math:** If Obius cannot demonstrate its value within the first note — not the third, not after reading a tutorial — most users will close it and never return. The section/intent/Handle/Echo mental model is powerful but requires learning. Apple Notes requires zero learning.

**Severity: Critical.** This is the single biggest existential risk. Every feature that adds cognitive load before value is delivered actively pushes users back to the default.

### Kill Shot 2: No Monetization Engine

The codebase defines `maxNotesForFreeUser: 100` but does not enforce it. There is no IAP, no subscription framework, no RevenueCat, no Stripe, no paywall screen. Obius would launch as a completely free app with no path to revenue.

**The math:** Obsidian makes ~$25M ARR from optional Sync ($4/mo) and Publish ($8/mo) across 1.5M MAU. Median free-to-paid conversion in App Store productivity apps is ~2.2%. At that rate, Obius would need ~45,000 MAU to reach just 1,000 paying users. At $5/mo that is $60K ARR — below the survival threshold for one full-time developer.

**Severity: Critical.** A product without a revenue model is a hobby. Ship a paywall before (or at the same time as) the public launch.

### Kill Shot 3: AI Is Simultaneously Overpromised and Unfinished

The marketing says "local-first notes with AI." The iOS client's Intelligence tab returns a hardcoded placeholder: "I'm not connected to an AI backend yet." The backend edge functions (embeddings, semantic search, summaries) work, but the user-facing AI feature is stubbed.

Meanwhile, every competitor now has AI. Notion shipped autonomous AI agents. Craft, Reflect, Mem, and Bear all have AI features in production. AI is no longer a differentiator — it is table stakes. Mem raised $28.6M on an "AI-first notes" thesis and is now widely described as a failure because the AI moat evaporated when OpenAI's APIs became commodity.

**Severity: High.** Either ship working AI that is genuinely better than the competition's, or remove AI from the positioning entirely. Promising AI and delivering a placeholder will generate 1-star reviews on day one.

### Kill Shot 4: The App Store Discovery Problem

The iOS productivity category is saturated. Approximately 1,249 new apps are published daily. Notion, Things, Obsidian, Craft, and GoodNotes dominate the top charts. Organic App Store search discovery for a new, unknown notes app is effectively zero.

There is no analytics or telemetry implementation in the codebase. No Amplitude, no Mixpanel, no Firebase Analytics — just a boolean flag that defaults to enabled. Without acquisition tracking, you cannot measure what brings users in, and without retention tracking, you cannot measure what keeps them.

**Severity: High.** You need an external acquisition channel (content marketing, community building, YouTube reviews, Product Hunt, indie hacker networks) before launch. Shipping to the App Store and hoping for organic discovery is not a strategy.

### Kill Shot 5: Sync Failures and Data Loss

Notes apps live or die by trust. Users will tolerate missing features but will never tolerate losing their data. The Obius sync architecture is well-designed (append-only changelog, per-device cursors, conflict resolution), but there is a `TODO: Apply merged entity to local database` comment in SyncEngine.swift suggesting conflict merge logic may not be fully implemented.

Evernote's decline began with sync reliability issues. Users who experience data loss or duplication do not file bug reports — they uninstall and warn others.

**Severity: High.** The sync engine must be the most tested code in the entire project. Ship with an explicit data export feature so users always have an escape hatch.

### Kill Shot 6: Trying to Be Everything for Everyone

The previous use-cases document lists eight industries. The codebase contains features for notes, sections, Handle Loops (portals), Echoes (reminders), a commit/versioning system, templates, AI search, AI summaries, audio recording, image attachments, and biometric locks. This is an enormous surface area for a pre-beta product with no visible test suite.

Obsidian succeeded by being great at one thing (local Markdown files with plugins). Bear succeeded by being great at one thing (beautiful, fast Apple-native notes). Roam succeeded initially by being great at one thing (bidirectional linking) — then stagnated trying to be everything.

**Severity: High.** Breadth is the enemy of quality at this stage. Every feature that is 80% done is worse than not having it at all, because it sets expectations and then disappoints.

### Kill Shot 7: Solo/Small Team vs. Funded Competitors

Notion has 800 employees and ~$500M ARR. Craft has raised significant funding. Even bootstrapped Obsidian has a mature team and 2,000+ community plugins providing free labor. Obius appears to be an early-stage project — 23,400 lines of Swift, two SPM dependencies, and an unchecked release checklist.

This is not automatically fatal (Bear and Obsidian started small), but it means every hour of development must be spent on what matters most. There is no room for building features nobody asked for.

**Severity: Medium.** Not a kill shot if the team is focused. Becomes fatal if the team tries to compete on feature breadth with Notion.

### Kill Shot 8: Apple-Only Platform Risk

Obius is iOS-only with a Supabase backend. No Android, no web, no desktop. Bear has survived this way, but Bear has an Apple Design Award and years of brand equity. For a new entrant, Apple-only means:

- Maximum addressable market is ~1.5B active Apple devices (vs. ~3.5B smartphones globally)
- No team/collaboration use cases (teams rarely standardize on one platform)
- One rejected App Store update can halt distribution

**Severity: Medium.** Acceptable if you deliberately choose Apple power users as your niche. Becomes a constraint if you need rapid scale.

### Kill Shot 9: Subscription Fatigue

Users are drowning in subscriptions. The average American has 12+ active subscriptions. Notability's switch from one-time purchase to subscription triggered a user revolt. Bear's $3/mo works because it is perceived as trivially cheap. Roam's $15/mo with no free tier killed its growth.

Median first-renewal churn on monthly plans is 15-40%. Barely 10% of monthly subscribers reach year two.

**Severity: Medium.** Pricing strategy must be decided early. A generous free tier with a single, compelling upgrade (like Obsidian's Sync) is safer than gating core features behind a paywall.

### Kill Shot 10: The Acqui-hire Exit

If Obius gains traction, a larger player (Notion, Apple, Craft) could offer to acquire the team and shut the product down — exactly what happened to Skiff (2M users, acquired by Notion, killed within 12 months). Users who chose Obius for its privacy and local-first principles would lose trust in the entire category.

**Severity: Low (but worth acknowledging).** This is an outcome, not a failure mode. But for a privacy-first product, the founding team's commitment to independence is part of the value proposition.

---

## Part 2 — Minimum Viable Market Segment

### The Wrong Approach: "Designed for Thinkers"

"Thinkers" is not a market segment. It is not searchable, targetable, measurable, or reachable through any specific channel. You cannot buy ads targeting "thinkers." You cannot find a subreddit for "thinkers." You cannot measure how many "thinkers" exist.

### The Framework: Who Has the Hair-on-Fire Problem?

The minimum viable segment must satisfy all five criteria:

1. **Specific and identifiable** — You can name them, find them, and count them
2. **Underserved by current tools** — Existing solutions cause real pain
3. **Willing and able to pay** — Not students, not hobbyists (at least not initially)
4. **Reachable through a specific channel** — Not "the App Store"
5. **Small enough to dominate, large enough to sustain** — 1,000-10,000 initial users

### Recommended First Segment: Independent Researchers and Analysts

**Who they are:** Freelance consultants, policy researchers, investigative journalists, independent analysts, think tank staff, and academic researchers outside traditional university IT ecosystems. People whose work product is structured analysis built from accumulated notes over weeks or months.

**Why they are underserved:**

| Pain Point | Current State | Why Obius Wins |
|---|---|---|
| Notes grow unwieldy over long projects | Notion pages become 50-screen scrolls. Apple Notes has no structure. Google Docs is linear. | Section-first architecture with collapse, nesting, and reordering was built for this exact problem. |
| Sensitive material in the cloud | Notion, Craft, and Mem store everything server-side. Researchers handling confidential sources, pre-publication findings, or privileged data cannot use these tools without risk. | Local-first + privacy mode = notes that never touch a server. |
| Connectivity is unreliable | Field researchers, traveling consultants, and journalists in the field need offline access. Most cloud-first tools degrade or fail offline. | Full offline capability with automatic sync on reconnect. |
| Finding old insights across projects | Keyword search fails when you remember the concept but not the exact words. Apple Notes search is basic. | Semantic search finds sections by meaning across the entire note collection. |
| Organizing by intent, not just topic | Existing tools force a choice: everything is a "note" or a "task" or a "bookmark." Research material is all three simultaneously. | Intent color-coding (idea, question, task, reference, important) adds lightweight metadata without forcing rigid categories. |

**Why they can pay:** Independent researchers and analysts charge $100-500+/hr for their work. A $5-10/mo tool that makes their core workflow faster is a trivial expense.

**Where to find them:**
- Substacks and newsletters covering policy, analysis, and investigation
- r/pkm, r/ObsidianMD, r/Zettelkasten (people actively seeking better tools)
- Academic Twitter/Mastodon communities
- Journalism Slack groups and press freedom organizations
- Product Hunt and Hacker News (indie tool discovery)
- YouTube PKM reviewers (Tiago Forte, Nick Milo, Nicole van der Hoeven audiences)

**How many exist:** The global management consulting market alone employs ~2.4M people. The freelance research/analysis segment is smaller but growing. A realistic initial target: 5,000 users in the first year, 500 paying ($30K-60K ARR).

### Why Not the Other Segments?

| Segment | Why Not First |
|---|---|
| Legal professionals | Regulated industry, long procurement cycles, need compliance certifications, enterprise sales |
| Healthcare | HIPAA/regulatory burden, institutional purchasing, not an individual decision |
| Students | High volume but extremely low willingness to pay, high churn at semester boundaries |
| Engineering teams | Team features (collaboration, sharing) required — Obius is single-user |
| Enterprise anything | Requires admin panels, SSO, audit logs, SOC 2 — none of which exist |
| General consumers | "Designed for everyone" means designed for no one. Apple Notes already owns this. |

### Expansion Path

```
Phase 1 (Months 0-12):  Independent researchers & analysts
                          └─ Prove the section-first model works for long-form research
                          └─ Prove willingness to pay
                          └─ Build testimonials and case studies

Phase 2 (Months 12-24): Adjacent solo professionals
                          └─ Freelance consultants
                          └─ Solo attorneys and paralegals
                          └─ Independent journalists
                          └─ Graduate students (PhD candidates)

Phase 3 (Months 24+):   Small team use cases
                          └─ Requires collaboration features
                          └─ Shared notes, team sync, admin controls
```

---

## Part 3 — The Killer Thesis

### What a Positioning Statement Must Do

It must answer three questions in one sentence:
1. **Who is it for?** (specific enough to exclude most people)
2. **What does it replace?** (the current painful alternative)
3. **Why is it dramatically better?** (not incrementally — dramatically)

### Candidates

**Option A (Research-focused):**
> Obius is a private, offline-first notes app that lets researchers and analysts structure, search, and resurface months of accumulated thinking — without trusting a cloud they don't control.

**Option B (Structure-focused):**
> Obius turns messy research into structured, searchable knowledge using collapsible sections and semantic search — all stored locally on your device, not someone else's server.

**Option C (Fear-focused):**
> Obius is the notes app for people who lost trust in cloud tools after watching Evernote decay and Skiff get killed — local-first, structured, and yours.

### Recommended: Option A

> **Obius is a private, offline-first notes app that lets researchers and analysts structure, search, and resurface months of accumulated thinking — without trusting a cloud they don't control.**

**Why this works:**

- **"researchers and analysts"** — Names the audience. Excludes casual users, which is correct.
- **"structure, search, and resurface"** — Three verbs that map to the three real features (sections, semantic search, AI summaries). No vague promises.
- **"months of accumulated thinking"** — Positions against the pain point. This is not for quick grocery lists. This is for people with hundreds of notes who need to find something from three months ago.
- **"without trusting a cloud they don't control"** — The emotional hook. Post-Evernote, post-Skiff, this resonates. It does not say "no cloud" (because sync exists) — it says you do not have to trust one.

---

## Appendix: Immediate Action Items

Based on this analysis, the highest-leverage actions before any public launch:

| Priority | Action | Why |
|---|---|---|
| **P0** | Wire up or remove the AI chat placeholder | A stubbed feature labeled "Intelligence" will generate 1-star reviews |
| **P0** | Implement and test the payment/subscription flow | No revenue = no business |
| **P0** | Stress-test sync with real multi-device scenarios | Data loss is an unrecoverable trust failure |
| **P1** | Add basic analytics (Mixpanel, PostHog, or TelemetryDeck) | You cannot improve what you cannot measure |
| **P1** | Build onboarding that demonstrates value in the first note | Show sections, collapse, intent — in 60 seconds |
| **P1** | Add data export (Markdown, JSON) | Users must know they can leave; this builds trust |
| **P2** | Reduce feature surface for v1 (consider hiding Handles and Echoes behind progressive disclosure) | Ship fewer things that work perfectly rather than many things that work mostly |
| **P2** | Build an external acquisition channel before App Store submission | Blog, community, beta waitlist, PKM newsletter partnerships |
