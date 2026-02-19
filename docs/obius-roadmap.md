# Obius Roadmap: What's Holding It Back, Where to Start, Where to Go

## What's Actually Holding This App Back

It is not a feature problem. The codebase has more working features than most shipped indie apps: sections with nesting, drag-and-drop, intent color-coding, Handle Loops (portals), Echoes (reminders), biometric locking, media (images + audio), templates, a full commit/versioning system, and multi-device sync. That is a lot of surface area.

**The problem is that the three things that would make Obius genuinely different from every competitor are either broken or missing:**

| Differentiator | Status in Code | What Users See |
|---|---|---|
| **AI assistance** | `IntelligenceView.swift:114` — placeholder that returns "I'm not connected to an AI backend yet" after a fake 1.5s delay | A feature labeled "Intelligence" that does nothing. Instant 1-star review material. |
| **.obx export** | `SettingsView.swift:150` — "Export All Notes" button exists, does nothing. No share sheet, no ActivityViewController, no DocumentPicker. | A promise of data ownership with no way to actually get data out. |
| **Payment** | Zero lines of StoreKit, RevenueCat, or IAP code anywhere in the project. `maxNotesForFreeUser: 100` defined in AppConfiguration but never checked. | A free app with no path to revenue. |

Everything else — notes, sections, commits, sync, handles, echoes — works. The core product is real. But the three things that would justify someone choosing Obius over Apple Notes are the three things that don't function.

**There is also a silent killer:** commits are 100% manual. The user must tap a context menu, choose "Commit Page" or "Commit Node," type a name, and confirm. Most users will never do this. Which means the entire .obx system — the most differentiated thing in the codebase — will sit unused. The commit library will be empty. The trust story will be invisible.

---

## Manual, Automated, or AI? The Commit Question

This is the most important product decision before launch.

### Option 1: Stay Manual (Current State)

The git analogy: commits are intentional snapshots. Users decide when something is worth preserving.

| Pros | Cons |
|---|---|
| Full user control | Most users will never commit — the feature becomes invisible |
| Commits are meaningful and named | The .obx library stays empty for 90%+ of users |
| Simple to maintain | The entire trust/portability story dies on the vine |

**Verdict:** Manual-only kills the differentiator. Developers understand commits. Researchers, analysts, journalists — the target segment — do not think in commits.

### Option 2: Fully Automated (Every Change = Commit)

Auto-snapshot on every significant edit, like Time Machine or Google Docs version history.

| Pros | Cons |
|---|---|
| Every user gets commits without thinking | Noise — hundreds of trivial snapshots |
| .obx library fills automatically | Storage bloat (every keystroke chain creates files) |
| Trust story is always visible | Loses intentionality — commits become meaningless backups |

**Verdict:** Too noisy. Turns a meaningful artifact system into a dumb backup log. Obsidian's file recovery plugin does this and nobody thinks of those snapshots as "artifacts."

### Option 3: Hybrid — Auto Checkpoints + Manual Commits (Recommended)

Two tiers of versioning:

```
TIER 1: Silent Checkpoints (automatic, invisible)
  Triggered by:
  - App moves to background (scenePhase → .background)
  - User closes a note (onDisappear)
  - Idle timeout (no edits for 5+ minutes, then any new edit triggers checkpoint of prior state)
  - Significant change threshold (e.g., 500+ characters changed since last checkpoint)

  These are:
  - Unnamed (auto-generated label like "Checkpoint · Feb 19, 3:42 PM")
  - Stored as .obx files in the vault (same Cold Store)
  - Visible in version history but visually distinct from manual commits
  - Lightweight — no user interaction required

TIER 2: Named Commits (manual, intentional)
  Triggered by:
  - User explicitly taps "Commit" (existing flow)
  - User provides a name and confirms

  These are:
  - Named by the user ("Draft 2", "Pre-review version", "Final analysis")
  - The .obx files that get exported and shared
  - The artifacts that carry the trust story
  - Visually prominent in the Library
```

**Why this works:**

1. **Every user gets version history for free** — checkpoints happen silently, so even users who never manually commit have recoverable snapshots
2. **Intentional commits remain meaningful** — when a user names a commit, it stands out from the auto-checkpoints
3. **The .obx export story stays clean** — export targets named commits, not every auto-checkpoint
4. **No AI required** — this is pure event-driven logic using infrastructure that already exists (CommitModule, ColdStore, scenePhase hooks)
5. **The Debouncer utility already exists** at `/Obius/Core/Utilities/Debouncer.swift` — currently unused for saves, ready to throttle checkpoint frequency

### Option 4: AI-Triggered Commits (Future, Not Now)

AI detects "meaningful change" and suggests or auto-creates commits.

| Pros | Cons |
|---|---|
| Smart — reduces noise while preserving meaning | AI features are currently placeholder (no backend connected) |
| Could suggest commit names based on content | Requires on-device model or API call for every change assessment |
| Feels magical when it works | Feels broken when it misjudges |

**Verdict:** This is a V3 feature. It requires working AI infrastructure, which does not exist today. The hybrid model (Option 3) gives 80% of the value with 0% AI dependency.

---

## The Roadmap

### Phase 0: Unblock the Launch (Do This First)

These are the items that must be complete before any public beta. They are ordered by dependency, not preference.

#### 0.1 — Remove or Fix the AI Placeholder

**Current state:** `IntelligenceView.swift:114-119` returns a hardcoded fake response after 1.5 seconds.

**Decision:**

| Option | Effort | Risk |
|---|---|---|
| **A: Remove the Intelligence tab entirely** | 1 day | None. A missing feature is better than a broken one. |
| **B: Wire up the existing Supabase edge functions** | 1-2 weeks | The backend functions exist (`generate-summary`, `semantic-search`, `generate-embedding`). The work is connecting them to the iOS UI and handling errors/loading states. |

**Recommendation:** Option A for beta launch. Option B for v1.1. A tab that says "Coming Soon" with a waitlist is better than a tab that lies.

#### 0.2 — Ship .obx Export via Share Sheet

**Current state:** "Export All Notes" button in Settings does nothing. No share/export anywhere.

**What to build:**

1. Single-commit export: tap a commit in the Library → share as `.obx` file (already JSON, just needs `UIActivityViewController`)
2. Bundled export: select a note → export all commits as a zip containing multiple `.obx` files + media
3. Full vault export: Settings → "Export All" → zip of entire vault directory

**Priority order:** Start with #1 (single commit share). It is the thinnest slice and immediately makes the trust story tangible. This is the feature you demo.

**Infrastructure needed:** `UIActivityViewController` or `ShareLink` (SwiftUI), zip creation via `Foundation` (no third-party dependency needed).

#### 0.3 — Implement Auto-Checkpoints (Hybrid Commit Model)

**Current state:** Commits are manual-only. `BGTaskScheduler` identifiers are declared in Info.plist (`app.obius.ios.sync`, `app.obius.ios.cleanup`) but no code registers or handles them.

**What to build:**

```swift
// Triggers for silent checkpoints:
// 1. scenePhase → .background (in ObiusApp.swift — currently only checks Echoes)
// 2. NoteEditorView.onDisappear (currently only cleans empty notes)
// 3. Idle timer via Debouncer (utility exists, unused for this purpose)

// Implementation:
// - CommitModule.createCheckpoint(noteId:) — same as createCommit but:
//   - No user-provided name (auto-label: "Checkpoint · {date}")
//   - Only creates if content changed since last checkpoint (hash comparison)
//   - Marked as type: .checkpoint (add to CommitType enum)
// - Library UI shows checkpoints in a collapsible "Auto-saved versions" group
//   below named commits
```

**Key constraint:** Only checkpoint if the content hash differs from the last commit/checkpoint. This prevents duplicate .obx files and storage bloat.

#### 0.4 — Implement Payment

**Current state:** Nothing.

**What to build:**

| Approach | Complexity | Notes |
|---|---|---|
| **RevenueCat + StoreKit 2** | Medium (1-2 weeks) | Handles receipts, entitlements, analytics. Industry standard for indie apps. |
| **Raw StoreKit 2** | Higher | More control, no dependency, but you build receipt validation yourself. |

**Recommended tier structure:**

```
Free Tier:
  - Unlimited notes and sections
  - Manual commits only
  - Local storage only (no sync)
  - Basic text search

Pro Tier ($4.99/mo or $39.99/yr):
  - Auto-checkpoints
  - .obx export
  - Cloud sync
  - Semantic search (when AI ships)
  - AI-generated titles (when AI ships)
```

**Why this split works:** Free users get a genuinely good notes app. Pro users get the commit system, export, and sync — the things that make Obius different. This matches Obsidian's model (free core, paid sync/publish).

---

### Phase 1: Core Loop (First 3 Months After Beta)

#### 1.1 — Onboarding That Demonstrates Value in 60 Seconds

**Current state:** Two buttons ("Sign In for Cloud Sync" or "Continue Offline"). No tutorial, no sample content, no feature introduction.

**What to build:**
- 3-screen walkthrough: (1) Create a section, (2) Set an intent color, (3) Collapse it
- Pre-loaded sample note that demonstrates sections, nesting, and intent — the user's first impression must show why this is different from Apple Notes
- Skip button for returning users

#### 1.2 — Background Sync

**Current state:** `BGTaskScheduler` identifiers declared in Info.plist but zero implementation code.

**What to build:**
- Register `app.obius.ios.sync` in `ObiusApp.swift` `init()`
- Handle background fetch: pull remote changes, push pending local changes
- Register `app.obius.ios.cleanup` for periodic vault maintenance (orphan detection via `ProfileScanner`)

#### 1.3 — Enforce Privacy Mode

**Current state:** Toggle exists in Settings UI. Standard vs Private mode. Not enforced in code — sync still runs regardless.

**What to build:**
- When Privacy Mode is on: disable `SyncEngine`, hide cloud-related UI, skip embedding/summary API calls
- Clear indicator in the UI that the app is in local-only mode

#### 1.4 — Analytics

**Current state:** A boolean `analyticsEnabled` flag. No analytics SDK.

**Recommendation:** TelemetryDeck (privacy-focused, indie-friendly, cheap) or PostHog (self-hostable, more powerful). Track:
- Notes created per user per week
- Commits created (manual vs auto-checkpoint)
- .obx exports triggered
- Sync success/failure rate
- Session duration and retention

---

### Phase 2: The Trust Story (Months 3-6)

#### 2.1 — .obx Import

**What it enables:** Users can receive .obx files from others and import them into their library. This is the first step toward .obx as an interchange format.

#### 2.2 — Markdown Export

**Why:** Not everyone wants .obx. Researchers who use Obsidian or plain text workflows need Markdown export as a secondary format. This expands the portability story.

#### 2.3 — Configurable Auto-Checkpoint Rules

**What it enables:** Users choose their checkpoint frequency and triggers. Power users might want checkpoints every 2 minutes. Others might want only on-close. Settings UI for this.

#### 2.4 — Commit Diff Viewer

**Current state:** `CommitModule.diffCommits()` exists and returns a `CommitDiff` with added/removed/modified sections. No UI for viewing diffs.

**What to build:** A visual diff view showing what changed between two commits. This makes the version history genuinely useful, not just a list of snapshots.

---

### Phase 3: AI That Matters (Months 6-12)

By this point, the core product is solid, the trust story is real, and users are paying. Now AI adds value on top of a working foundation.

#### 3.1 — Wire Up Semantic Search

**Current state:** `SyncEngine.semanticSearch()` exists, calls `supabase.invokeFunction("semantic-search")`, returns `[SemanticSearchResult]`. `SearchView.swift:50` uses basic text search only.

**What to build:** Replace or augment `SearchView` to call semantic search when the user's query does not match exact text. Display results ranked by relevance with source note context.

#### 3.2 — Wire Up Embeddings

**Current state:** `SyncEngine.generateEmbeddings()` exists, calls `supabase.invokeFunction("generate-embedding")`. Never triggered.

**What to build:** Trigger embedding generation when a note is committed (manual commit only — not checkpoints, to manage API costs). Store embedding reference in commit metadata.

#### 3.3 — AI-Generated Titles

**Current state:** `Note.aiTitle` field exists. `SyncEngine.generateSummary()` exists, calls `supabase.invokeFunction("generate-summary")`. Never triggered from UI.

**What to build:** After a manual commit, offer to generate a title/summary. Show it as a suggestion the user can accept or dismiss. Never overwrite user-provided titles.

#### 3.4 — AI-Suggested Commit Points

**The V3 feature:** AI monitors editing patterns and suggests "You've made significant changes to this note. Commit?" This requires:
- On-device change detection (diff size, time since last commit, semantic shift)
- A lightweight model or heuristic (does not need a full LLM — change magnitude + time threshold is sufficient)
- A non-intrusive suggestion UI (banner, not modal)

#### 3.5 — Related Section Discovery

**Current state:** No implementation at all — not in code, not in backend functions.

**What to build:** Using embeddings from 3.2, find sections across different notes that are semantically related. Surface these as "Related" suggestions when viewing a section. This is the "connections you didn't know existed" feature that PKM enthusiasts crave.

---

### Phase 4: Protocol (Year 2+)

This phase only happens if Phases 0-3 succeed and .obx gains real adoption.

#### 4.1 — Publish the .obx Specification

Open-source the format spec. Document the JSON schema, hash algorithm, parent chain structure, media reference format. Let anyone build tools that read/write .obx.

#### 4.2 — External Timestamp Verification

Integrate RFC 3161 timestamp authority or a similar external witness. This moves .obx from "integrity" (content has not changed) to "authenticity" (content provably existed at this time).

#### 4.3 — Import/Export Bridges

Build converters: Obsidian Markdown → .obx, Notion export → .obx, .obx → Markdown. The more tools that can read .obx, the more defensible the format becomes.

#### 4.4 — Verification Tool

A standalone web tool or CLI that takes an .obx file and verifies its hash chain, timestamp, and content integrity. This is what makes "trust protocol" real — anyone can verify, not just Obius.

---

## The One-Page Summary

```
WHAT'S HOLDING OBIUS BACK:
  Not features (there are plenty). Three specific gaps:
  1. AI that lies (placeholder responses)
  2. Export that doesn't work (button does nothing)
  3. No way to pay (zero payment code)
  Plus: commits are manual-only, so the best feature goes unused.

WHERE TO START:
  Phase 0 — in this order:
  1. Remove fake AI tab (1 day)
  2. Ship single-commit .obx export via share sheet (3-5 days)
  3. Add auto-checkpoints on background/close/idle (1 week)
  4. Implement payment via RevenueCat (1-2 weeks)

THE COMMIT MODEL:
  Hybrid. Auto-checkpoints (silent, event-driven) + manual named commits.
  No AI needed. AI-suggested commits are a V3 feature.

THE FULL SEQUENCE:
  Phase 0: Unblock launch (fix AI, ship export, auto-checkpoints, payment)
  Phase 1: Core loop (onboarding, background sync, privacy enforcement, analytics)
  Phase 2: Trust story (.obx import, Markdown export, diff viewer, configurable rules)
  Phase 3: AI that matters (semantic search, embeddings, auto-titles, suggested commits)
  Phase 4: Protocol (open spec, external verification, bridges, verification tool)

WHAT NOT TO DO:
  - Do not build AI automation before the core loop works
  - Do not declare a protocol before the format has users
  - Do not add more features before the existing ones are shippable
  - Do not try to serve 8 industries before dominating one segment
```
