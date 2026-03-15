# Obius: Insights & Page Mapping — Visual Analysis

---

## Part 1: Insight Engine — What Gets Created

### Insight Generation Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    InsightEngine.scan()                       │
│                                                              │
│  1. Filter deleted notes                                     │
│  2. Garbage-collect orphaned insights                        │
│  3. Fetch all sections grouped by note                       │
│  4. Run detectors ──────────────────────────┐                │
│  5. Deduplicate against existing insights   │                │
│  6. Bulk-insert new insights                │                │
│  7. Purge dismissed > 30 days               │                │
└─────────────────────────────────────────────┘                │
                                              │                │
              ┌───────────────────────────────┘                │
              ▼                                                │
┌─────────────────────────────────────────────────────────────┐
│                     DETECTOR MATRIX                          │
├──────────────┬───────────────┬───────────┬──────────────────┤
│   CLEANUP    │   REMINDERS   │  SAFETY   │  UPCOMING ECHO   │
│   (gray)     │   (orange)    │  (red)    │  (orange)        │
├──────────────┼───────────────┼───────────┼──────────────────┤
│ ● Stale      │ ● Tasks       │ ● API Key │ ● Firing now     │
│ ● Dormant    │ ● Questions   │ ● Pwd     │ ● Within 24h     │
│ ● Lonely     │ ● Sugg. Echo  │ ● SSN     │                  │
│ ● Nonsense   │   (AI-powered)│ ● CC#     │                  │
├──────────────┼───────────────┼───────────┼──────────────────┤
│ Max: 5+5+3+3 │ Unlimited     │ Max: 10   │ Max: 5           │
│ = 16 total   │ (1 per note)  │ total     │                  │
└──────────────┴───────────────┴───────────┴──────────────────┘
```

### Detailed Insight Subtypes

```
INSIGHT TYPE        SUBTYPE          ICON                        TINT     DETECTION METHOD
─────────────────────────────────────────────────────────────────────────────────────────────
CLEANUP             stale            clock.arrow.circlepath      gray     Unpinned + not updated in 14+ days
                    dormant_loop     moon.zzz                    gray     Handle not updated in 14+ days
                    lonely_loop      link                        gray     Handle referenced only once, no active echo
                    nonsense         trash.circle                red      <10 meaningful chars OR >80% non-alphabetic

REMINDER            task             checkmark.circle            green    Regex: "todo:", "[ ]", "need to", "should", etc.
                    question         questionmark.bubble         yellow   Ends with "?", starts with who/what/when/etc.
                    suggested_echo   bell.and.waves.*            orange   AI (Claude via Supabase) temporal extraction

SAFETY              api_key          key                         red      Regex: sk-*, pk_*, AKIA* patterns
                    password         lock.shield                 red      Regex: password/pwd/secret/token := value
                    personal_data    person.badge.shield.*       red      Regex: SSN (###-##-####), CC (16 digits)

UPCOMING ECHO       (sectionId)      bell.badge                  orange   EchoManager: fireDate within [-1h, +24h]

──── PHASE 2 (NOT YET IMPLEMENTED) ────
DRIFT               -                safari                      blue     AI: off-topic detection, orphan tags
WEEKLY REPORT       -                chart.bar.doc.horizontal    purple   AI: activity digest
PROGRESS            -                gauge.with.dots.*           green    AI: project health score
```

### Insight Lifecycle

```
                ┌──────────────┐
                │   SCAN()     │
                │  (detector)  │
                └──────┬───────┘
                       │ creates
                       ▼
              ┌────────────────┐
              │   SURFACED     │◄─── New insight, visible to user
              │                │
              └───┬────────┬───┘
                  │        │
         track()  │        │ dismiss()
                  ▼        ▼
         ┌──────────┐  ┌───────────┐
         │ TRACKED   │  │ DISMISSED  │
         │ (pinned)  │  │           │
         └─────┬─────┘  └─────┬─────┘
               │              │
      untrack()│              │ after 30 days
               ▼              ▼
         ┌──────────┐  ┌───────────┐
         │ SURFACED  │  │  PURGED   │
         │ (again)   │  │ (deleted) │
         └──────────┘  └───────────┘
```

### Deduplication Strategy

```
dedupKey = "{insightType}|{sourceNoteId}|{sourceSectionId}"

Examples:
  "cleanup|note-abc|stale"           → 1 stale insight per note
  "reminder|note-xyz|task"           → 1 task insight per note (consolidated count)
  "safety|note-def|api_key"          → 1 API key insight per note
  "upcomingEcho|note-ghi|section-jk" → 1 per echo per section

Result: Prevents duplicate insights across repeated scans
```

---

## Part 2: Page Mapping — How Pages Are Organized

### Page Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                         MODULE (Folder)                          │
│                     filtered by moduleId                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─── PINNED ──────────────────────────────────────────────┐    │
│  │                                                          │    │
│  │  ┌─── BLOCK (groupName) ───────────────────────┐        │    │
│  │  │  ● Note A   (auto-pinned when grouped)      │        │    │
│  │  │  ● Note B   (auto-pinned when grouped)      │        │    │
│  │  └─────────────────────────────────────────────┘        │    │
│  │                                                          │    │
│  │  ● Note C (standalone pinned, no group)                  │    │
│  │  ● Note D (standalone pinned, no group)                  │    │
│  │                                                          │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─── UNPINNED ────────────────────────────────────────────┐    │
│  │  ● Note E (newest updatedAt first)                       │    │
│  │  ● Note F                                                │    │
│  │  ● Note G                                                │    │
│  │  ● ...                                                   │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Note Sort Order (Ranking)

```
SQL: ORDER BY isPinned DESC, updatedAt DESC

RANK   CRITERIA                 WEIGHT
────────────────────────────────────────────────
 #1    isPinned = true          Always on top
 #2    updatedAt DESC           Most recently edited first
 #3    (implicit) groupName     Grouped notes auto-pinned
────────────────────────────────────────────────

Result:
  1. Pinned notes first (including all Block members)
  2. Within each tier: most recently updated first
  3. No engagement scoring, no frequency weighting, no tag-based boosting
```

### Section Drill-Down (Möbius Navigation)

```
NOTE (Root Level)
│
├── Section A (orderKey: "A")          ◄── Visible at root
│   ├── Section A.1 (parent: A)       ◄── Visible after drillInto("A")
│   │   └── Section A.1.1 (parent: A.1)   ◄── Visible after drillInto("A.1")
│   └── Section A.2 (parent: A)
│
├── Section B (orderKey: "B")          ◄── Visible at root
│
├── [interstitial text: after_B]       ◄── Free text between sections
│
└── Section C (orderKey: "C")          ◄── Visible at root

Navigation Stack: [] → ["A"] → ["A", "A.1"]
Breadcrumb:       Note > Section A > Section A.1
```

### Section Ordering: Fractional Index

```
FractionalIndex.between("A", "C") → "B"
FractionalIndex.between("A", "B") → "AN"  (midpoint in ASCII)
FractionalIndex.after("C")        → "D"
FractionalIndex.before("A")       → "5"   (midpoint before "A")

Purpose: Allows O(1) insertion between any two sections
         without reindexing the entire list
```

### Note Content Model

```
┌─────────────────────────────────────────────────┐
│ NOTE                                             │
│                                                  │
│ ┌──── body (direct note text) ─────────────────┐│
│ │ "Meeting notes from Monday..."                ││
│ └───────────────────────────────────────────────┘│
│                                                  │
│ ┌──── Section 1 (fold/line) ───────────────────┐│
│ │ intent: .task  │  handleId: @design-review    ││
│ │ content: "Review the mockups"                 ││
│ │ contentType: .text / .checklist / .code / ... ││
│ └───────────────────────────────────────────────┘│
│                                                  │
│ ┌──── interstitial["after_sec1"] ──────────────┐│
│ │ "Additional context between sections..."      ││
│ └───────────────────────────────────────────────┘│
│                                                  │
│ ┌──── Section 2 ───────────────────────────────┐│
│ │ intent: .evidence  │  parentSectionId: nil    ││
│ │ isLocked: true (biometric)                    ││
│ └───────────────────────────────────────────────┘│
│                                                  │
│ ┌──── interstitial["end"] ─────────────────────┐│
│ │ "Final thoughts..."                           ││
│ └───────────────────────────────────────────────┘│
│                                                  │
│ tags: ["#project", "#urgent"]                    │
│ aiTags: ["meeting", "design", "review"]          │
│ intent: .idea                                    │
│ moduleId: "workspace-123"                        │
│ groupName: "Sprint 12"  (→ auto-pinned)          │
└─────────────────────────────────────────────────┘
```

---

## Part 3: Ranking Analysis & Improvement Suggestions

### Current Ranking Assessment

| Dimension | Current State | Score | Notes |
|-----------|--------------|-------|-------|
| **Note ordering** | `isPinned DESC, updatedAt DESC` | 4/10 | Binary pin + recency only. No signal richness. |
| **Insight ordering** | `createdAt DESC` | 3/10 | Newest first, no priority/severity weighting. |
| **Search ranking** | FTS5 with BM25 | 7/10 | Solid text relevance. No personalization. |
| **Section ordering** | Fractional index (manual) | 8/10 | Clean design. User-controlled. Works well. |
| **Insight detection** | Heuristic regex + thresholds | 5/10 | Good coverage, but high false-positive risk. |
| **Insight dedup** | String-key matching | 6/10 | Simple and effective. Could miss near-dupes. |
| **Phase 2 features** | Stubbed (drift, weekly, progress) | 0/10 | Not yet implemented. |

### Improvement Suggestions (Ranked by Impact)

#### 1. **Insight Priority Scoring** — HIGH IMPACT
**Problem:** All insights sort by `createdAt DESC`. A safety alert (leaked API key) has the same visual priority as a stale note cleanup suggestion.

**Suggestion:** Add a `priority` field computed from insight type + subtype:
```
PRIORITY MAP:
  safety/api_key        → P0 (critical)
  safety/password       → P0
  safety/personal_data  → P0
  upcomingEcho (firing) → P1 (urgent)
  reminder/task         → P2 (actionable)
  reminder/question     → P3 (informational)
  upcomingEcho (soon)   → P3
  cleanup/nonsense      → P4 (housekeeping)
  cleanup/stale         → P5 (low)
  cleanup/dormant_loop  → P5
  cleanup/lonely_loop   → P5

Sort: priority ASC, createdAt DESC
```

#### 2. **Smart Note Ranking** — HIGH IMPACT
**Problem:** Notes are ranked purely by pin status + last-edit time. A note you view 20x/day but haven't edited ranks below one you edited once yesterday.

**Suggestion:** Introduce a lightweight engagement score:
```
score = (isPinned ? 1000 : 0)
      + (recencyBoost)          // decay curve based on updatedAt
      + (viewCount * 2)         // track note opens
      + (sectionCount * 1)      // richer notes rank higher
      + (hasActiveEcho ? 50 : 0) // notes with echoes are active
      + (insightCount * -5)     // notes with many cleanup insights rank lower
```

#### 3. **Reduce False Positives in Task Detection** — MEDIUM IMPACT
**Problem:** The task detector casts a very wide net. Phrases like "I should go to bed" or "we need to talk about the design" will trigger task insights for conversational notes.

**Suggestion:**
- Add a confidence score to each match (explicit markers like `[ ]` = high, phrases like "should" = low)
- Only surface low-confidence matches if the note's intent is NOT `.idea` or `.evidence`
- Consider requiring 2+ matches for phrase-based detection
- Filter out notes shorter than ~50 words (likely not actionable)

#### 4. **Insight Consolidation per Category** — MEDIUM IMPACT
**Problem:** The Intelligence view can show up to ~16 cleanup + unlimited reminder insights. Users with many notes could be overwhelmed.

**Suggestion:**
- Group by category with a count badge, only show top 3 per category
- Add a "severity" indicator: `🔴 2 safety • 🟡 5 tasks • ⚪ 8 cleanup`
- Provide a "weekly digest" summary that collapses insights into trends

#### 5. **Module-Aware Insight Scoping** — MEDIUM IMPACT
**Problem:** Insights scan ALL notes globally. The Intelligence view filters by module afterwards, but the scan work + cap limits apply globally.

**Suggestion:** Pass `moduleId` into `scan()` so caps (e.g., max 5 stale notes) apply per-module, not globally. Users working in multiple modules currently might not see insights for smaller modules.

#### 6. **Question Detection Refinement** — LOW IMPACT
**Problem:** Any line ending with `?` and 4+ words is flagged. "Is this good?" inside a conversational note generates noise.

**Suggestion:**
- Exclude notes with intent `.question` (already categorized by user)
- Add a minimum content length threshold for question detection
- Weight standalone questions (entire section is a question) higher than inline ones

#### 7. **Implement Phase 2: Drift Detection** — FUTURE
**Problem:** Currently stubbed. Off-topic notes and orphan tags go undetected.

**Suggestion:** Use the existing AI proxy (`ClaudeService`) to:
- Compare note content against module-level topic clusters (from `aiTags`)
- Flag notes where AI-generated tags have zero overlap with module's common tags
- Detect orphan tags (user tags referenced only once)

#### 8. **Page Mapping: Tag-Based Clustering** — FUTURE
**Problem:** Notes within a module are a flat list. No automatic grouping by topic.

**Suggestion:**
- Use `aiTags` to cluster notes into virtual groups
- Show a "Related Pages" section when viewing a note
- Allow auto-grouping: notes with 3+ shared aiTags get suggested as a Block

---

## Summary Scorecard

```
┌──────────────────────────────┬──────────┬───────────────────────┐
│ AREA                         │ MATURITY │ TOP ACTION            │
├──────────────────────────────┼──────────┼───────────────────────┤
│ Insight Detection (heuristic)│ ████░░░░ │ Add confidence scores │
│ Insight Detection (AI)       │ ██░░░░░░ │ Implement Phase 2     │
│ Insight Prioritization       │ █░░░░░░░ │ Add priority scoring  │
│ Insight Lifecycle            │ ██████░░ │ Good — minor tuning   │
│ Note Ranking                 │ ███░░░░░ │ Engagement scoring    │
│ Section Ordering             │ ████████ │ Solid — no changes    │
│ Search (FTS5 + BM25)        │ ██████░░ │ Add personalization   │
│ Navigation (Möbius)          │ ████████ │ Solid — no changes    │
│ Deduplication                │ █████░░░ │ Near-dupe detection   │
│ Module Scoping               │ ████░░░░ │ Module-aware scanning │
└──────────────────────────────┴──────────┴───────────────────────┘
```
