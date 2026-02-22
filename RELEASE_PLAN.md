# Obius Release Plan — Intelligence Page & Insights

## Tier Philosophy

**Free = everything local.** Pro = cloud + AI + full intelligence.

| Layer | Free | Pro |
|-------|------|-----|
| Notes, Sections, Intent Tags | Yes | Yes |
| Handles & Handle Loops | Yes | Yes |
| Commits (manual + auto) | Yes | Yes |
| Echoes | Yes | Yes |
| Modules | Yes | Yes |
| Cloud Sync | No | Yes |
| Sharing & Share Links | No | Yes |
| AI Editor Actions (E1-E4) | No | Yes |
| Intelligence Tab — Teaser | Yes (2-3 insights) | Full (all 20) |
| Commit View Counts | N/A (requires sharing) | Yes (existing) |

### Intelligence Tab Tier Split

**Free teaser insights (always available, local SQLite):**

| # | Insight | Rationale |
|---|---------|-----------|
| I4 | Open Tasks | Universally useful, lightweight task aggregator — hooks users |
| I11 | Stale Notes | Easy win, surfaces forgotten work — drives engagement |
| I20 | Weekly Thinking Summary | Creates the habit loop of opening Intelligence tab |

**Pro insights (requires subscription):**

| # | Insight | Reason for Pro |
|---|---------|---------------|
| I1 | Unanswered Questions | High-value professional insight |
| I2 | Unsupported Ideas | High-value professional insight |
| I3 | Orphaned Evidence | Professional reasoning tool |
| I5 | Incomplete Reasoning Chain | Premium reasoning analysis |
| I6 | Concept Clusters | Cross-note analysis |
| I7 | Similar Sections Across Notes | Requires AI (embeddings) |
| I8 | Tag Overlap | Cross-note analysis |
| I9 | Handle Candidates | Partial AI |
| I10 | Reasoning Evolution | Commit analysis |
| I12 | Abandoned Threads | Commit diff analysis |
| I13 | Significant Changes | Commit diff analysis |
| I14 | Ready to Share | Requires sharing (Pro) |
| I15 | Uncommitted Work | Pro nudge feature |
| I16 | Echo Check-In | Pro |
| I17 | Shared Content Activity | Requires sharing (Pro) |
| I18 | Intent Distribution | Pro analytics |
| I19 | Concept Momentum | Pro analytics |

### Editor Actions Tier Split

| # | Action | Tier |
|---|--------|------|
| E1 | Suggest Title | Pro (requires Claude API) |
| E2 | Summarize Note | Pro (requires Claude API) |
| E3 | Auto-Tag Sections | Free: basic heuristic (? = Question, action verbs = Task). Pro: Claude-powered accuracy |
| E4 | Find Related Sections | Pro (requires embeddings + pgvector) |

---

## What's Already Built

### Fully Implemented
- [x] Notes, Sections with intent tags (idea/question/task/evidence)
- [x] #tag system on notes (stored as JSON array, parsed by HashtagHelper)
- [x] Handles & Handle Loops
- [x] Commit system (manual + auto-commits with .obx cold storage)
- [x] Echoes (recurring reminders, fire dates, intervals)
- [x] Share links with view count tracking
- [x] Comments/Handshakes on shared content (with sealed hashes)
- [x] Cloud sync (Supabase sync-push/sync-pull)
- [x] Auth (Supabase Auth, biometric lock)
- [x] `generate-summary` edge function (Claude — titles + summaries)
- [x] `generate-embedding` edge function (OpenAI — 1536-dim vectors)
- [x] `semantic-search` edge function (pgvector cosine similarity)
- [x] Commit view counts aggregated from share links (eye icon in commit rows)
- [x] 2-tab structure: Notes + Library
- [x] Editor toolbar with: Pin, Intent picker, Commit Page, Share, Delete

### Exists but Placeholder
- [~] IntelligenceView.swift — currently a non-functional chat UI, needs complete redesign to insights feed

### Not Built
- [ ] Intelligence tab in the tab bar (only 2 tabs exist: Notes, Library)
- [ ] Insight models & computation engine
- [ ] Any insight cards or insight feed UI
- [ ] Editor AI actions wired into the toolbar (Suggest Title, Summarize, Auto-Tag, Find Related)
- [ ] Subscription/payment infrastructure (no StoreKit, no paywall, no tier gate)
- [ ] Pro/Free tier checking logic
- [ ] Insight dismissal persistence
- [ ] Insight "new" badge tracking
- [ ] Feed refresh strategy implementation

---

## What's Left for Release (v1.0)

### Priority 1: Subscription Infrastructure
_Must ship before anything is gated._

1. **StoreKit 2 integration**
   - Product IDs, subscription group
   - Monthly/yearly Pro subscription
   - Restore purchases
   - Receipt validation

2. **ProStatusManager**
   - `isProUser: Bool` observable state
   - Persisted locally + verified against App Store
   - Gate checks throughout the app

3. **Paywall View**
   - Shown when user taps Pro-gated features
   - Feature comparison (Free vs Pro)
   - Subscription options
   - Restore button

4. **Tier gates**
   - Cloud sync: gated behind Pro
   - Sharing: gated behind Pro
   - AI editor actions: gated behind Pro
   - Intelligence tab: show teaser free, paywall on Pro insights

### Priority 2: Intelligence Tab — Core Architecture

5. **Insight model**
   ```
   struct Insight: Identifiable {
       let id: String
       let type: InsightType          // enum of I1-I20
       let category: InsightCategory  // gaps/connections/evolution/readiness/patterns
       let title: String              // the finding
       let description: String        // detail
       let noteIds: [String]          // source notes
       let sectionIds: [String]       // source sections
       let actionLabel: String        // CTA text
       let priority: Int              // sort weight
       let isNew: Bool                // since last visit
       let createdAt: Date
       let requiresPro: Bool
   }
   ```

6. **InsightEngine (computation)**
   - Protocol-based: each insight type is a separate `InsightProvider`
   - Runs local SQLite queries against NoteRepository, SectionRepository, CommitRepository
   - Returns `[Insight]` sorted by priority
   - Lightweight — all v1.0 insights are local queries, no API calls

7. **Redesign IntelligenceView → InsightsFeedView**
   - Replace chat UI with card feed
   - Insight cards grouped by category
   - Dismiss action per card (persisted)
   - "New" badge on unseen cards
   - Empty state: "Your thinking is in good shape. Check back later."
   - Locked cards for Pro insights (with paywall trigger)
   - Cap at 8-10 visible cards

8. **Add Intelligence as 3rd tab**
   - Tab bar: Notes | Intelligence | Library
   - Brain icon for Intelligence tab
   - Badge count for new insights

### Priority 3: v1.0 Free Insights (ship in release)

9. **I4 — Open Tasks** (FREE)
   - Query: sections WHERE intent = 'task' (unchecked checklists or task-tagged text)
   - Group by note
   - Card: task sections grouped by note title

10. **I11 — Stale Notes** (FREE)
    - Query: notes WHERE updatedAt < 14 days ago AND updatedAt > 60 days ago
    - Bonus: flag if note has open tasks or unanswered questions
    - Card: note title, last edit date, open item count

11. **I20 — Weekly Thinking Summary** (FREE)
    - Aggregate: notes edited, sections created, commits made this week
    - Intent tag transitions (question → has evidence = "answered")
    - Card: clean numbers summary

### Priority 4: v1.0 Pro Insights

12. **I1 — Unanswered Questions** (PRO)
    - Query: notes with sections WHERE intent = 'question' but no sections with intent = 'evidence'
    - Card: note titles, question previews

13. **I6 — Concept Clusters** (PRO)
    - Query: GROUP notes BY tags, surface clusters of 3+ notes sharing a tag
    - Card: tag name, note titles

14. **I15 — Uncommitted Work** (PRO)
    - Query: notes with 2+ sections and zero commits
    - Card: note titles, section counts

15. **I16 — Echo Check-In** (PRO)
    - Query: echoes WHERE nextFireDate within 24 hours
    - Card: echo description, fire time, linked note

16. **I17 — Shared Content Activity** (PRO)
    - Query: share links WHERE viewCount increased since last check
    - Card: share title, view count, new views

### Priority 5: Editor AI Actions (v1.0, Pro only)

17. **E1 — Suggest Title**
    - Add sparkle button near title field in NoteEditorView
    - Calls existing `generate-summary` edge function
    - Inline suggestion: tap to accept, swipe to dismiss
    - Gated behind Pro

### Priority 6: v1.1 Insights (post-release)

18. **I5 — Incomplete Reasoning Chain**
19. **I2 — Unsupported Ideas**
20. **I3 — Orphaned Evidence**
21. **I18 — Intent Distribution** (bar chart of intent types this week)
22. **I19 — Concept Momentum** (most active #tags this week)
23. **I8 — Tag Overlap** (pairs of notes with 3+ shared tags)
24. **E3 — Auto-Tag Sections** (heuristic v1 free, Claude v2 Pro)
25. **E2 — Summarize Note** (Pro, Claude)

### Priority 7: v1.2 Insights (future)

26. **I10 — Reasoning Evolution**
27. **I13 — Significant Changes**
28. **I14 — Ready to Share**
29. **I12 — Abandoned Threads**
30. **I9 — Handle Candidates**
31. **I7 — Similar Sections Across Notes** (embeddings)
32. **E4 — Find Related Sections** (embeddings)

---

## Commit View Tracking

**Decision: Keep as-is.** View counts on commits come from share link views (the `get-shared-content` edge function increments `view_count`). The commits list already aggregates these by `commitHash` and displays with an eye icon. This is sufficient and already built.

---

## Feed Refresh Strategy (v1.0)

- **On app foreground:** Recompute all local-query insights (cheap SQLite)
- **On tab switch to Intelligence:** Refresh feed
- **Cap:** 8-10 visible cards max
- **Dismissal:** Persisted per insight+note combo, reappears only if underlying data changes
- **New badge:** Track `lastInsightsViewedAt` timestamp, mark cards created after that as "new"

---

## Build Order Summary

| Phase | What Ships | Key Deliverables |
|-------|-----------|-----------------|
| **v1.0 Release** | Subscription + Intelligence tab + 8 insights + E1 | StoreKit, paywall, InsightsFeedView, 3 free insights (I4, I11, I20), 5 Pro insights (I1, I6, I15, I16, I17), Suggest Title (E1) |
| **v1.1** | 7 more insights + 2 editor actions | I2, I3, I5, I8, I18, I19 + Auto-Tag (E3), Summarize (E2) |
| **v1.2** | Remaining insights + embedding features | I7, I9, I10, I12, I13, I14 + Find Related (E4) |

---

## Files That Need Changes (v1.0)

| File | Change |
|------|--------|
| `ContentView.swift` | Add 3rd tab (Intelligence), wire up InsightsFeedView |
| `IntelligenceView.swift` | Complete rewrite → InsightsFeedView (insights card feed) |
| **New:** `Models/Insight.swift` | Insight model, InsightType enum, InsightCategory enum |
| **New:** `Core/InsightEngine.swift` | Computation engine with InsightProvider protocol |
| **New:** `Core/Providers/OpenTasksProvider.swift` | I4 computation |
| **New:** `Core/Providers/StaleNotesProvider.swift` | I11 computation |
| **New:** `Core/Providers/WeeklySummaryProvider.swift` | I20 computation |
| **New:** `Core/Providers/UnansweredQuestionsProvider.swift` | I1 computation |
| **New:** `Core/Providers/ConceptClustersProvider.swift` | I6 computation |
| **New:** `Core/Providers/UncommittedWorkProvider.swift` | I15 computation |
| **New:** `Core/Providers/EchoCheckInProvider.swift` | I16 computation |
| **New:** `Core/Providers/SharedActivityProvider.swift` | I17 computation |
| **New:** `Views/Intelligence/InsightCardView.swift` | Individual insight card UI |
| **New:** `Views/Intelligence/LockedInsightCardView.swift` | Pro-gated card with paywall trigger |
| **New:** `Core/ProStatusManager.swift` | StoreKit 2 subscription state |
| **New:** `Views/Paywall/PaywallView.swift` | Subscription purchase UI |
| `NoteEditorView.swift` | Add Suggest Title button (E1) to toolbar/menu |
| `NoteEditorViewModel.swift` | Add `suggestTitle()` calling generate-summary |
| `AppState.swift` | Add InsightEngine, ProStatusManager |
| `ObiusApp.swift` | Initialize ProStatusManager |
