# OBIUS App Viability Analysis

## What OBIUS Is

OBIUS is a native iOS note-taking app (Swift/SwiftUI, ~32K LOC, 97 files) with a Supabase backend. It positions itself as "the Cursor of ideas" — an AI-powered thinking tool where ideas are living, linked, and evolving entities rather than static text.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Pages** | Notes with rich structure (body + interstitial text between sections) |
| **Nodes/Sections** | Atomic content blocks (text, checklist, code, quote, image, audio). Collapsible, lockable (biometric), nestable |
| **Intent Types** | Semantic color-coding: Idea (blue), Question (yellow), Task (green), Evidence (purple) |
| **Handles/Loops** | Named reusable content blocks (`@name`). Portal-linked — edit one, all update |
| **Echoes** | Spaced-repetition reminders on Loops. Recurring or one-time |
| **Commits** | Git-style immutable snapshots. SHA-256 hashed, content-addressable, parent-chained |
| **Modules** | Folder containers (local or cloud) |
| **Intelligence** | Insight engine: stale notes, tasks, safety issues (API keys), upcoming echoes |
| **Semantic Search** | pgvector-powered meaning-based search |
| **AI Integration** | Claude Haiku with tool use — AI suggests and executes actions on your knowledge base |
| **Share Links** | Public sharing via `obius.io/s/{slug}` — live or immutable snapshots, with comments |

---

## VC Investor Perspective

### Exciting
- Loop + Echo system is genuinely novel (Zettelkasten + Anki + Git)
- Deep architectural moats (commit system, portal-linked content, semantic search)
- AI integrated structurally (tools that modify data), not as a chatbot
- Local-first architecture with sync is the right call

### Concerns
- iOS-only severely limits TAM
- No visible monetization (no subscription, no paywall, no IAP)
- Extremely high concept density — learning curve risk
- Solo developer risk
- Crowded market (Apple Notes, Notion, Obsidian, Reflect, Mem, Capacities)

**Verdict: Pass at this stage, watch closely.** Need evidence of PMF, web/cross-platform, simplified onboarding, and monetization plan.

---

## CEO Perspective

### Strategic Priorities
1. Kill or hide half the features for v1. Progressive disclosure.
2. Web app is non-negotiable. Thinking tool must work at a desk.
3. Freemium with AI tiers: Free (limited AI), Pro $8/mo, Team $15/user/mo.
4. Rename confusing concepts. Simplify terminology.
5. Target one persona first: indie hackers, researchers, or writers.

**Verdict: Real product buried under complexity. Simplify ruthlessly, ship web, charge money.**

---

## Future User Perspective

### Pull Factors
- Intent system (Idea/Question/Task/Evidence) is intuitive
- Semantic search across all notes
- Biometric lock on sections
- Immutable snapshot sharing
- Personality and taste in the UX copy

### Push Factors
- Confusing terminology (Handles, Loops, Folds, Lines)
- No web version for desk work
- Privacy concerns around AI insight scanning
- No collaboration / co-editing

**Verdict: Would try it, be impressed, get confused, leave. Would return if simplified with web access.**

---

## Business Viability

### Current State (iOS-only)
- Realistic market: ~500K people
- Realistic conversion: 2-5K paying users
- **$192K-$480K ARR** — lifestyle business

### With Platform Expansion + Simplification
- Cross-platform expands TAM 10x
- Simplified onboarding improves activation 5x
- B2B/team features increase ACV from $96/yr to $2,400/yr
- **Path to $5-10M ARR in 3-4 years**

---

## Bottom Line

The vision is excellent. The engineering is impressive. The product needs brutal simplification and platform expansion.

- **Biggest risk:** Shipping an IDE when people want a magic notepad
- **Biggest opportunity:** Nobody has nailed "living, linked, evolving ideas" yet

The core insight — that ideas should be linked, revisited on a cadence, and version-controlled — is powerful and underserved. Execution requires focus.
