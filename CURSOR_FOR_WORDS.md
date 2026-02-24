# Obius: Cursor for Words

## The Thesis

Cursor proved you can build a massive company by embedding AI into an existing workflow (coding) instead of replacing it. The same opportunity exists for thinking-over-time, and nobody owns it.

Obius isn't an AI chat app that stores notes. It's a **thinking environment** where AI is ambient — woven into the act of writing, connecting, and revisiting ideas. You don't "switch to AI mode." The system is always understanding what you write, surfacing what's relevant, and keeping your loops alive.

The AI disappears into the tool.

---

## What Cursor Gets Right (That We Steal)

| Cursor Pattern | Obius Translation |
|---|---|
| **Codebase indexing** — Cursor knows your entire project | **Thought indexing** — Obius knows your entire writing history via embeddings |
| **Tab autocomplete** — suggests the next line of code | **Connection suggest** — surfaces related ideas, contradictions, loop opportunities as you write |
| **Cmd+K inline edit** — select code, transform with AI | **Section actions** — tap a section, AI develops/connects/challenges it |
| **Chat with context** — chat that knows your whole repo | **Chat with memory** — chat that knows every note you've ever written |
| **Background linting** — catches issues you didn't ask about | **Ambient intelligence** — detects stale thinking, missed connections, evolving themes |

The key insight: **Cursor doesn't generate code for you. It makes YOU faster at coding.** Obius doesn't think for you. It makes you faster at thinking.

---

## Architecture: 5 Layers

```
┌─────────────────────────────────────────────────┐
│  Layer 5: Smart Echoes                          │
│  Echoes arrive with AI-generated briefings      │
├─────────────────────────────────────────────────┤
│  Layer 4: Ambient Intelligence                  │
│  Background detection of patterns & evolution   │
├─────────────────────────────────────────────────┤
│  Layer 3: Section Actions (Cmd+K)               │
│  On-demand AI transforms for selected content   │
├─────────────────────────────────────────────────┤
│  Layer 2: Inline Suggestions (Tab)              │
│  Real-time connection/loop suggestions as you   │
│  write                                          │
├─────────────────────────────────────────────────┤
│  Layer 1: Context Engine (Indexing)             │
│  Embeddings + semantic retrieval + context      │
│  assembly                                       │
├─────────────────────────────────────────────────┤
│  Layer 0: API Proxy (Infrastructure)            │
│  All AI calls through Supabase Edge Functions   │
└─────────────────────────────────────────────────┘
```

Each layer builds on the one below it. Ship them in order.

---

## Layer 0: API Proxy Migration

**Why first:** Everything else requires metering, caching, and model routing. Can't do that with API keys hardcoded in the iOS app.

### What Changes

**Current flow:**
```
iOS App → Anthropic API (direct, API key in app bundle)
iOS App → OpenAI API (via Supabase Edge Function)
```

**New flow:**
```
iOS App → Supabase Edge Functions → Anthropic API
iOS App → Supabase Edge Functions → OpenAI API
```

### New Edge Functions

| Function | Replaces | Purpose |
|---|---|---|
| `ai-chat` | Direct ClaudeService calls | Chat with tools (schedule_echo, edit_handle, etc.) |
| `ai-generate-title` | ClaudeService.generateTitle() | Title generation |
| `ai-generate-tags` | ClaudeService.generateTags() | Tag/concept extraction |
| `ai-extract-entities` | ClaudeService.extractEntities() | Entity detection for loop suggestions |
| `ai-extract-echoes` | ClaudeService.extractTemporalEchoes() | Temporal phrase detection |
| `ai-suggest` | ClaudeService.detectAISuggestions() | Insight generation |

### Shared Infrastructure (Edge Function side)

```typescript
// supabase/functions/_shared/ai-router.ts

interface AIRequest {
  userId: string;
  feature: string;        // "chat" | "title" | "tags" | "entities" | etc.
  model?: string;         // Override model selection
  messages: Message[];
  tools?: Tool[];
  maxTokens: number;
}

interface AIResponse {
  content: string;
  toolUse?: ToolUseBlock[];
  usage: {
    inputTokens: number;
    outputTokens: number;
    model: string;
    estimatedCostUsd: number;
  };
}

// Model routing: use cheap models for cheap tasks
function selectModel(feature: string): string {
  switch (feature) {
    case "chat": return "claude-sonnet-4-20250514";
    case "title": return "claude-haiku-4-5-20251001";
    case "tags": return "claude-haiku-4-5-20251001";
    case "suggest": return "claude-sonnet-4-20250514";
    default: return "claude-haiku-4-5-20251001";
  }
}
```

### Usage Tracking Table

```sql
-- New migration
CREATE TABLE ai_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  feature TEXT NOT NULL,
  model TEXT NOT NULL,
  input_tokens INT NOT NULL,
  output_tokens INT NOT NULL,
  estimated_cost_usd NUMERIC(10, 6) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ai_usage_user_date ON ai_usage (user_id, created_at);

-- RLS: users can only see their own usage
ALTER TABLE ai_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own usage"
  ON ai_usage FOR SELECT USING (auth.uid() = user_id);
```

### iOS Changes

Replace `ClaudeService` direct API calls with Supabase function invocations:

```swift
// Before (direct API call)
func generateTitle(from content: String) async throws -> String {
    let request = AnthropicRequest(model: "claude-haiku-4-5-20251001", ...)
    let response = try await URLSession.shared.data(for: request)
    ...
}

// After (proxy through Supabase)
func generateTitle(from content: String) async throws -> String {
    let response = try await supabase.functions.invoke(
        "ai-generate-title",
        options: .init(body: ["content": content])
    )
    ...
}
```

**Estimated scope:** ~3 days. 6 new edge functions, 1 migration, ClaudeService rewrite.

---

## Layer 1: Context Engine

**The foundation.** Like Cursor's codebase indexing, but for your thought history.

### What It Does

Given what you're currently writing, instantly retrieve the most relevant content from your entire note corpus. This powers every layer above it.

### Components

#### 1a. Embedding Pipeline (enhance existing)

Current state: `generate-embedding` edge function embeds sections on demand.

Needed:
- **Auto-embed on write**: When a section is created or updated, queue embedding generation
- **Embed loop content**: Handle content changes trigger re-embedding
- **Embed interstitials**: Body text and interstitial content get embedded too
- **Staleness tracking**: Know when embeddings are outdated

```sql
-- Add to sections table
ALTER TABLE sections ADD COLUMN embedding_updated_at TIMESTAMPTZ;

-- Add to handles table
ALTER TABLE handles ADD COLUMN embedding vector(1536);
ALTER TABLE handles ADD COLUMN embedding_updated_at TIMESTAMPTZ;
```

**Trigger:** After sync push, if content changed, queue embedding update. This keeps it async and doesn't block the writing experience.

#### 1b. Context Retrieval Function

New edge function: `ai-context`

```typescript
// supabase/functions/ai-context/index.ts

interface ContextRequest {
  userId: string;
  query: string;              // Current section content or user query
  excludeNoteId?: string;     // Don't return content from current note
  maxResults?: number;        // Default 10
  includeHandles?: boolean;   // Include loop content
  recencyBias?: number;       // 0-1, weight toward recent content
}

interface ContextResult {
  sections: {
    id: string;
    noteId: string;
    noteTitle: string;
    content: string;
    similarity: number;
    updatedAt: string;
  }[];
  handles: {
    id: string;
    name: string;
    content: string;
    similarity: number;
    portalCount: number;      // How many places reference this loop
  }[];
}
```

This is the single retrieval endpoint that every AI feature calls. It replaces the ad-hoc context building happening in `IntelligenceView.buildRichContext()`.

#### 1c. Context Assembly

Server-side function that takes retrieval results and builds a prompt context block:

```typescript
function assembleContext(results: ContextResult): string {
  let context = "## Your relevant notes and loops:\n\n";

  for (const handle of results.handles) {
    context += `### Loop: @${handle.name} (referenced in ${handle.portalCount} places)\n`;
    context += `${handle.content}\n\n`;
  }

  for (const section of results.sections) {
    context += `### From "${section.noteTitle}" (${timeAgo(section.updatedAt)}):\n`;
    context += `${section.content}\n\n`;
  }

  return context;
}
```

**Estimated scope:** ~4 days. Embedding pipeline enhancement, new edge function, context assembly.

---

## Layer 2: Inline Suggestions

**The "Tab" equivalent.** As you write, Obius surfaces connections without you asking.

### How It Works

1. User writes/edits a section
2. After 3-second debounce (longer than current 5s entity extraction — replace it), iOS sends the section content to a new edge function
3. Server queries the context engine for related content
4. Server runs a fast Claude call to classify the connection type
5. iOS shows a subtle suggestion card below the section

### Suggestion Types

| Type | Example | Action |
|---|---|---|
| **Connection** | "Related to what you wrote in 'Q3 Planning' 2 weeks ago" | Tap to view side-by-side |
| **Contradiction** | "You wrote the opposite in 'Budget Review': '...'" | Tap to reconcile |
| **Loop opportunity** | "You've mentioned 'onboarding process' in 4 notes" | Tap to create loop |
| **Echo suggestion** | "This seems time-sensitive — revisit Thursday?" | Tap to set echo |
| **Existing loop** | "@project_roadmap is related — link it here?" | Tap to insert portal |

### Edge Function: `ai-inline-suggest`

```typescript
// supabase/functions/ai-inline-suggest/index.ts

interface InlineSuggestRequest {
  userId: string;
  sectionId: string;
  sectionContent: string;
  noteId: string;
}

interface InlineSuggestion {
  type: "connection" | "contradiction" | "loop_opportunity" | "echo" | "existing_loop";
  title: string;           // Short display text
  detail: string;          // Supporting context
  sourceNoteId?: string;   // Related note
  sourceSectionId?: string;
  handleId?: string;       // For existing_loop type
  confidence: number;      // 0-1, only show above threshold
}
```

**Model choice:** Haiku for classification (fast + cheap). Only call Sonnet if the user acts on a suggestion.

### iOS UI: SuggestionCard

Appears below the active section, dismissible:

```
┌──────────────────────────────────────────┐
│ 🔗 Related to "Q3 Planning" (2 weeks ago)│
│ "We decided to delay the rebrand..."     │
│                          [View] [Dismiss]│
└──────────────────────────────────────────┘
```

Design principles:
- **Subtle.** Small card, muted colors. Not a banner, not a modal.
- **Dismissible.** Swipe away. System learns from dismissals.
- **One at a time.** Never stack multiple suggestions. Show highest confidence only.
- **No autocomplete of text.** We're completing *connections*, not words. The user writes. We connect.

### Replaces

- Current entity extraction (5s debounce → EntitySuggestionBanner) — subsumed by loop_opportunity suggestions
- Part of InsightEngine's AI detection — real-time is better than batch

**Estimated scope:** ~5 days. New edge function, SuggestionCard component, NoteEditorViewModel integration, debounce + threshold tuning.

---

## Layer 3: Section Actions (Cmd+K Equivalent)

**On-demand AI for the current section.** The user asks for help on a specific piece of writing, with full context.

### Trigger

Long-press a section (or tap a toolbar button) to open the **Action Bar**:

```
┌──────────────────────────────────────────┐
│ ✨ Develop  🔗 Connect  🔄 Loop         │
│ ⚡ Simplify  🎯 Challenge  ✏️ Refine    │
└──────────────────────────────────────────┘
```

Or: a text field for free-form instructions (like Cursor's Cmd+K prompt).

### Actions

| Action | What AI Does | Context Needed |
|---|---|---|
| **Develop** | Expands the thought with supporting reasoning | Current section + related sections from context engine |
| **Connect** | Finds and explains connections to other notes | Current section + top 10 semantic matches |
| **Loop** | Promotes to loop with AI-suggested name | Current section + existing handle names |
| **Simplify** | Distills to core point | Current section only |
| **Challenge** | Plays devil's advocate using your own past writing | Current section + contradicting/contrasting sections |
| **Refine** | Improves clarity without changing meaning | Current section only |
| **Free-form** | User types custom instruction | Current section + context engine results |

### Response: Inline Diff

Like Cursor's inline edit suggestions, show the AI's proposed changes as a diff within the section:

```
┌─ Section ─────────────────────────────────┐
│ The onboarding process needs to be faster │ (original, dimmed)
│                                           │
│ The onboarding process needs to be faster.│ (AI suggestion, highlighted)
│ Currently taking 3 weeks on average, the  │
│ bottleneck is the compliance review step  │
│ you identified in @hiring_pipeline. A     │
│ parallel review could cut this to 5 days. │
│                                           │
│              [Accept] [Edit] [Dismiss]    │
└───────────────────────────────────────────┘
```

For **Connect** actions, show a connection card instead of a diff:

```
┌─ Connections ─────────────────────────────┐
│ 3 related ideas found:                    │
│                                           │
│ 1. "Q3 Planning" → "rebrand timeline"     │
│    Written 2 weeks ago, marked as task    │
│                                           │
│ 2. @project_roadmap → "phase 2 hiring"    │
│    Loop referenced in 4 notes             │
│                                           │
│ 3. "Retro Notes" → "process bottlenecks"  │
│    You flagged this as a question          │
│                                           │
│           [Link first] [View all] [Done]  │
└───────────────────────────────────────────┘
```

### Edge Function: `ai-section-action`

```typescript
interface SectionActionRequest {
  userId: string;
  action: "develop" | "connect" | "simplify" | "challenge" | "refine" | "custom";
  sectionId: string;
  sectionContent: string;
  noteId: string;
  customPrompt?: string;     // For free-form
  context?: ContextResult;   // Pre-fetched or let server fetch
}

interface SectionActionResponse {
  type: "diff" | "connections" | "suggestion";
  proposedContent?: string;  // For diff type
  connections?: Connection[]; // For connections type
  explanation: string;       // Always present: what AI did and why
}
```

**Model choice:** Sonnet for all section actions (quality matters here — user explicitly asked for help).

**Estimated scope:** ~6 days. Edge function, ActionBar UI, inline diff component, connection card component, keyboard toolbar integration.

---

## Layer 4: Ambient Intelligence

**Background detection** that runs without user prompting. The existing InsightEngine, but upgraded.

### What Changes From Current InsightEngine

| Current | New |
|---|---|
| Pattern-matching regexes (local) | Semantic analysis via context engine (server) |
| AI detection with 5-min cooldown | Continuous background analysis on content change |
| Flat list of insights | Tiered by signal strength (per STRATEGY_REVIEW.md) |
| Batch analysis of top 10 notes | Incremental: analyze what changed since last scan |

### New Detection Capabilities

| Detector | What It Finds | How |
|---|---|---|
| **Evolving themes** | "Your thinking about X has shifted from Y to Z over 3 months" | Track embedding drift over time |
| **Attention gaps** | "You haven't revisited @project_x in 3 weeks despite 5 related notes" | Cross-reference echo activity with note activity |
| **Contradiction detector** | "In note A you say X, in note B you say not-X" | High-similarity + sentiment divergence in embeddings |
| **Convergence detector** | "These 4 notes are circling the same idea — consolidate?" | Embedding cluster analysis |
| **Completion detector** | "3 of 5 tasks in @hiring_pipeline are done — close it out?" | Track checklist/intent state across loop portals |

### Architecture

```
Content changes (via sync)
  → Queue analysis job (debounced per user, 30s)
  → Edge function: ai-ambient-scan
    → Fetch recent changes since last scan
    → Query context engine for related content
    → Run detection prompts (Haiku — cheap, frequent)
    → Store new insights in insights table
  → iOS pulls new insights on next sync
  → Insights appear on Home tab
```

**Key principle:** This runs server-side, async, after sync. The user never waits for it. Insights just appear.

**Estimated scope:** ~5 days. New edge function, InsightEngine refactor, insight types expansion, sync integration.

---

## Layer 5: Smart Echoes

**Echoes arrive with context, not just a ping.**

### Current Echo Experience

```
Notification: "Echo: @project_roadmap — Every 3 days"
User opens app → sees EchoContextCard with last 3 portal references
User navigates to note → reads the loop → acknowledges
```

### New Echo Experience

```
Notification: "Echo: @project_roadmap — 3 things changed since last time"
User opens app → sees Smart Echo Card:

┌─ Echo: @project_roadmap ──────────────────┐
│ Last reviewed: 5 days ago                  │
│                                            │
│ Since then:                                │
│ • You added a new section in "Q3 Planning" │
│   mentioning timeline concerns             │
│ • @hiring_pipeline (linked) was updated    │
│   with 2 new candidates                    │
│ • Your tone shifted from "on track" to     │
│   "at risk" across related notes           │
│                                            │
│ Suggested focus:                           │
│ The timeline concern in Q3 Planning may    │
│ conflict with the roadmap's Phase 2 dates. │
│                                            │
│        [Open Loop] [Acknowledge] [Snooze]  │
└────────────────────────────────────────────┘
```

### How It Works

When an echo fires:
1. `EchoManager` detects fired echo (existing logic)
2. New: calls `ai-echo-brief` edge function before showing card
3. Edge function:
   - Fetches the loop's current content
   - Queries context engine for all sections mentioning this loop
   - Compares against state at `lastAcknowledgedAt` timestamp
   - Generates a briefing via Claude (Haiku — needs to be fast)
4. iOS shows enriched EchoContextCard with the briefing

### Adaptive Cadence (v2)

After the briefing system works:
- Track user engagement with each echo (opened? acknowledged? snoozed? time spent?)
- AI recommends cadence adjustment:
  - High engagement + frequent edits → "Suggest increasing to every 2 days"
  - Low engagement + stale content → "This loop hasn't changed in a month. Pause echoes?"
- User confirms cadence changes (never auto-adjust without consent)

**Estimated scope:** ~4 days. New edge function, EchoContextCard enhancement, briefing generation.

---

## Implementation Order & Dependencies

```
Phase 0: API Proxy          ████░░░░░░░░░░░░  ~3 days
         ↓
Phase 1: Context Engine     ░░░░████░░░░░░░░  ~4 days
         ↓
Phase 2: Inline Suggestions ░░░░░░░░████░░░░  ~5 days
         ↓ (can parallel with 3)
Phase 3: Section Actions    ░░░░░░░░░░████░░  ~6 days
         ↓
Phase 4: Ambient Intel      ░░░░░░░░░░░░██░░  ~5 days
         ↓
Phase 5: Smart Echoes       ░░░░░░░░░░░░░░██  ~4 days
```

**Total: ~27 days of implementation work across 5 phases.**

Phases 2 and 3 can overlap (different UI surfaces, same context engine). Phase 4 and 5 can also overlap.

Realistic timeline with testing and iteration: **6-8 weeks**.

---

## What This Replaces / Subsumes

| Existing Feature | Fate |
|---|---|
| `ClaudeService` direct API calls | **Replaced** by proxy edge functions |
| `InsightEngine` local pattern detectors | **Keep** as fast local fallback, supplement with server-side |
| `InsightEngine` AI detectors | **Replaced** by ambient intelligence (Layer 4) |
| Entity extraction (5s debounce) | **Replaced** by inline suggestions (Layer 2) |
| `IntelligenceView` chat | **Keep** but powered by context engine instead of manual `buildRichContext()` |
| `buildRichContext()` | **Replaced** by context engine retrieval |
| FAB + LoopComposeSheet (planned) | **Keep** — still valuable for multi-loop operations. Works with proxy. |
| `edit_handle` tool (planned) | **Keep** — integrates with section actions and chat. |

---

## What NOT To Build

- **Text autocomplete.** We're not completing sentences. We're completing connections. Generating text is what makes you a wrapper. Connecting ideas is what makes you a thinking tool.
- **AI-generated notes.** The user writes. Always. AI operates on what they wrote.
- **Voice/chat as primary interface.** The editor is primary. Chat is supplementary. If chat becomes the main thing, you're a ChatGPT skin.
- **"Agent" branding.** Don't call features "agents." Users don't want agents. They want their notes to be smarter. The intelligence is invisible.
- **Prompt templates / prompt library.** That's ChatGPT thinking. Section actions have fixed, opinionated behaviors. "Develop this thought" is not a prompt the user writes — it's a button that does something specific.

---

## Cost Model

With all layers active, estimated per-user daily cost:

| Layer | Calls/day | Model | Est. cost/day |
|---|---|---|---|
| Titles + tags | ~5 | Haiku | $0.001 |
| Inline suggestions | ~30 | Haiku (classify) + embedding query | $0.005 |
| Section actions | ~5 | Sonnet | $0.015 |
| Ambient intelligence | ~3 scans | Haiku | $0.003 |
| Smart echo briefings | ~2 | Haiku | $0.002 |
| Chat | ~5 messages | Sonnet | $0.015 |
| Embeddings | ~20 sections | text-embedding-3-small | $0.001 |

**Estimated: ~$0.04/user/day = ~$1.20/user/month**

At a $5-10/month subscription, this is viable with healthy margins. Heavy users might cost $0.10/day ($3/month) — still profitable at $7+/month.

**Cost controls:**
- Haiku for everything except user-initiated actions (section actions, chat)
- Embedding caching (don't re-embed unchanged content)
- Suggestion throttling (max 1 suggestion per 30 seconds)
- Ambient scan batching (don't scan on every keystroke — batch per sync cycle)
- Usage caps per tier (free: 20 AI actions/day, pro: unlimited)

---

## The Litmus Test

After all 5 layers ship, ask:

1. **Can the user turn off AI and still use Obius?** Yes — loops, echoes, sections, the editor all work without AI. It's just manual. ✅
2. **Does the AI serve the user's primitives, or is it the primitive?** It serves loops, echoes, sections. It doesn't generate for the sake of generating. ✅
3. **Is the intelligence ambient or modal?** Ambient. Suggestions appear without asking. Actions are one tap. Chat is fallback. ✅
4. **Could you build this on top of Apple Notes?** No — you need loops, echoes, sections, embeddings. The data model IS the moat. ✅
5. **Would removing Claude and using GPT-4 change the product?** Minimally. The model is replaceable. The system isn't. ✅

That last point is the whole game. **The moat is the system, not the model.**
