# Implementation Plan: AI-Loop Integration (FAB + @-Tagging + edit_handle)

## Overview

Add a floating action button (FAB) to the Intelligence page that opens a focused compose sheet where users can @-tag loops, pull them into AI context, and have Claude summarize, refine, or edit them — with a path toward saved "agents" (reusable loop+prompt combinations).

This is the highest-value feature addition after the Library tab removal. It turns the AI from a passive observer of loops into an active collaborator.

---

## What Exists Today

| Component | Status | Location |
|-----------|--------|----------|
| `HandleManager.updateContent(handleId:content:)` | Ready | `HandleManager.swift:129` |
| `HandleManager.searchHandles(query:)` | Ready | `HandleManager.swift:114` |
| `HandleManager.findMentionedHandles(in:)` | Ready | `HandleManager.swift:93` |
| `HandleManager.detectMentions(in:)` | Ready | `HandleManager.swift:82` |
| `ClaudeService.sendWithTools()` | Ready | `ClaudeService.swift:69` |
| `SuggestedAction` + `ActionCardView` | Ready | `SuggestedAction.swift`, `ActionCardView.swift` |
| `IntelligenceView` with chat + insight cards | Ready | `IntelligenceView.swift` |
| `buildRichContext()` (sends handle names, NOT content) | Needs enhancement | `IntelligenceView.swift:533` |

**Key finding:** `HandleManager` already has full write APIs. The `@mention` regex pattern already exists. The confirmation card pattern already works. This is mostly wiring, not new architecture.

---

## Implementation: 4 Changes

### Change 1: Add `edit_handle` Tool to ClaudeService

**File:** `Obius-iOS/Obius/Core/Network/ClaudeService.swift`

Add a 4th tool definition to `toolDefinitions`:

```swift
[
    "name": "edit_handle",
    "description": "Edit the content of an existing handle (loop). The user will see a diff of the proposed changes and must approve before it executes.",
    "input_schema": [
        "type": "object",
        "properties": [
            "handle_id":     ["type": "string", "description": "The UUID of the handle to edit"],
            "handle_name":   ["type": "string", "description": "The display name of the handle (for the confirmation card)"],
            "new_content":   ["type": "string", "description": "The proposed new content for the handle"],
            "edit_summary":  ["type": "string", "description": "Brief description of what was changed (1 sentence)"]
        ],
        "required": ["handle_id", "handle_name", "new_content", "edit_summary"]
    ] as [String: Any]
]
```

Also update the system prompt in `sendWithTools()` to include guidance:
```
When the user provides loop content as context, you can suggest edits to those loops using the edit_handle tool.
Describe what you changed in edit_summary. The user will see a before/after diff.
```

### Change 2: Add `editHandle` Case to SuggestedAction

**File:** `Obius-iOS/Obius/Models/SuggestedAction.swift`

Add to `ActionType` enum:
```swift
case editHandle(EditHandleParams)
```

Add params struct:
```swift
struct EditHandleParams {
    let handleId: String
    let handleName: String
    let newContent: String
    let editSummary: String
}
```

Add to display properties:
- `icon`: `"pencil.line"`
- `title`: `"Edit @\(p.handleName)"`
- `description`: `p.editSummary`
- `toolName`: `"edit_handle"`
- `tintColor`: `.green`

Add to `from(toolUseBlock:)` factory for parsing.

Add to `execute(appState:)`:
```swift
case .editHandle(let p):
    try await HandleManager.shared.updateContent(handleId: p.handleId, content: p.newContent)
```

**Enhancement for ActionCardView:** For `editHandle` actions, show a before/after diff in the card. The "before" content can be fetched from `HandleManager.shared.getContent(handleId:)` at render time.

### Change 3: FAB + Compose Sheet on IntelligenceView

**File:** `Obius-iOS/Obius/Views/Intelligence/IntelligenceView.swift`

#### 3a. Add the FAB

Overlay on the existing `VStack`:

```swift
.overlay(alignment: .bottomTrailing) {
    Button {
        showComposeSheet = true
    } label: {
        Image(systemName: "at")  // or "bubble.left.and.text.bubble.right"
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Color.accentColor)
            .clipShape(Circle())
            .shadow(radius: 4)
    }
    .padding(.trailing, 20)
    .padding(.bottom, 70) // above the input bar
}
```

#### 3b. New Compose Sheet

**New file:** `Obius-iOS/Obius/Views/Intelligence/LoopComposeSheet.swift`

A sheet with:

1. **Loop selector area** (top) — shows selected loops as dismissible chips
   - @-mention text field that filters `HandleManager.shared.searchHandles(query:)` as you type
   - Tapping a suggestion adds it as a chip
   - Each chip shows `@handle_name` with intent color spine

2. **Prompt area** (middle) — TextEditor for the user's instruction
   - Placeholder: "Summarize, refine, compare..."
   - Supports free-form text

3. **Send button** (bottom right) — fires the request

**On send:**
1. Gather selected loop IDs
2. Fetch full content for each: `HandleManager.shared.getContent(handleId:)`
3. Build focused context string with full loop content:
   ```
   Selected Loops:
   - @budget (id: xxx): [full content here]
   - @expenses (id: xxx): [full content here]
   ```
4. Call `ClaudeService.sendWithTools()` with this focused context
5. Dismiss sheet, show response in the existing chat section (with action cards if Claude used tools)

### Change 4: Enhance `buildRichContext()` for @-mentions in Regular Chat

**File:** `Obius-iOS/Obius/Views/Intelligence/IntelligenceView.swift`

When the user types `@budget` in the regular input bar (not the FAB), detect it and inject that loop's full content into context.

In `buildRichContext(for:)`, after the existing handle summary, add:

```swift
// Inject full content for any @-mentioned handles in the query
let mentionedHandles = HandleManager.shared.findMentionedHandles(in: query)
if !mentionedHandles.isEmpty {
    let handleDetails = mentionedHandles.map { handle in
        "  - @\(handle.displayName) (id: \(handle.id)):\n    \(handle.content)"
    }
    parts.append("Referenced loop content:\n\(handleDetails.joined(separator: "\n"))")
}
```

This means even the inline chat bar gets smarter about loops — the FAB is for focused multi-loop work, the chat bar for quick @-references.

---

## v2: Saved Agents (Future)

Once the FAB + @-tagging is working, "agents" become a natural extension:

### Data Model

```swift
struct Agent {
    var id: String
    var name: String              // e.g. "Budget Review"
    var handleIds: [String]       // The loops this agent works with
    var prompt: String            // The saved instruction
    var createdAt: Int64
    var lastRunAt: Int64?
}
```

### How It Works
1. User uses the FAB to tag @budget + @expenses and types "summarize and flag discrepancies"
2. AI responds with useful output
3. User taps "Save as Agent" on the response
4. Agent appears in the Intelligence page (new section: "Your Agents")
5. Tapping an agent re-runs it with fresh loop content
6. Could be scheduled (like an Echo but for AI analysis instead of reminders)

### Where Agents Live in the UI
- Intelligence page gets a new horizontal scroll section: "Agents"
- Each agent is a chip showing its name + loop count
- Tap to run, long-press to edit/delete

**Not implementing agents in v1** — get the manual FAB workflow right first, then save patterns users actually repeat.

---

## File Change Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `ClaudeService.swift` | Modify | Add `edit_handle` tool definition, update system prompt |
| `SuggestedAction.swift` | Modify | Add `.editHandle` case, params, parsing, execution |
| `ActionCardView.swift` | Modify | Add diff display for edit_handle actions |
| `IntelligenceView.swift` | Modify | Add FAB button, `showComposeSheet` state, enhance `buildRichContext()` |
| `LoopComposeSheet.swift` | **New file** | Compose sheet with @-tag picker + prompt input |

**No new data models needed for v1.** No database changes. No new tabs. No new navigation patterns. The HandleManager write APIs and ActionCard confirmation pattern already exist.

---

## UX Flow

```
Intelligence Page
  |
  |-- [FAB button, bottom-right]
  |     |
  |     +-- LoopComposeSheet opens
  |           |-- Type @ to search loops
  |           |-- Select @budget, @expenses (shown as chips)
  |           |-- Type: "Summarize these and highlight conflicts"
  |           |-- [Send]
  |           |
  |           +-- Sheet dismisses
  |               Chat shows Claude's response
  |               If Claude used edit_handle:
  |                 ActionCard shows with before/after diff
  |                 [Accept] -> loop content updates everywhere
  |                 [Dismiss] -> nothing changes
  |
  |-- [Existing input bar]
        |-- Type: "What did I write about @budget?"
        |-- buildRichContext() detects @budget, injects full content
        |-- Claude responds with context-aware answer
```

---

## Why This Works

1. **No new paradigms** — @-mentioning handles is already the app's core interaction pattern
2. **No new confirmation UX** — uses existing ActionCardView + accept/dismiss flow
3. **No new data storage** — HandleManager.updateContent() already exists and syncs everywhere
4. **Incremental** — each change is independently useful and testable
5. **Path to agents** — the manual FAB workflow naturally evolves into saved workflows
