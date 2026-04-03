# Obius

A local-first note-taking app for iOS and macOS built with SwiftUI. Obius structures notes into reorderable, collapsible sections with semantic tagging, reusable content loops, version history, and AI-powered intelligence — all backed by a local SQLite database with optional cloud sync.

<p align="center">
  <img src="assets/Obius%20logo%20clean%20(black%20back).PNG" alt="Obius Logo" width="200"/>
</p>

## Features

### Structured Notes
- Notes are composed of **sections** (nodes and lines) that can be collapsed, reordered via drag-and-drop, and nested with indent levels
- Each section carries a semantic **intent** — Idea, Question, Task, or Evidence — with distinct color coding
- Rich content types: text, checklists, code blocks, quotes, images, and audio
- Sections can be locked behind biometric authentication (Face ID / Touch ID)

### Loops (Handles)
- Reusable named content blocks prefixed with `@` (e.g., `@grocery_list`)
- Link a section to a loop to create a **portal** — edits to the loop propagate to every linked section across all notes
- Manage loops from a dedicated library view

### Echoes (Reminders)
- Time-based alerts tied to loops with one-time or recurring schedules
- Native push notifications with fire-date tracking and acknowledgment state

### Commits (Version History)
- Immutable snapshots of a note's state stored in a cold-store archive (`.obx` files)
- Auto-commit runs daily for modified notes
- Browse and restore from any previous commit

### Share Links
- Generate public URLs to a live note or a frozen commit snapshot
- Short, human-readable slugs (e.g., `obius.io/s/AbC1xYzZ`) with view-count tracking

### Intelligence & Workspace
- AI-powered title generation, semantic search, and entity extraction
- Insight detection for safety issues (leaked keys/passwords), cleanup suggestions, list detection, and cross-note concept linking
- Interactive **Workspace** terminal panel (macOS) for chat and edit interactions with AI

### Modules
- Organize notes into modules (folders) with local and cloud-backed options

### Templates
- Template sections with bold, uneditable prefixes for repeatable note structures

## Architecture

```
Obius-iOS/
  Obius/
    App/              # ObiusApp entry point, ContentView root
    Configuration/    # Info.plist, AppConfiguration, xcconfig
    Core/
      Auth/           # Supabase authentication, biometric lock
      Database/       # GRDB connection pool, schema migrations (v1-v16)
      Network/        # Supabase client, Claude API service
      Storage/        # Cold store (.obx archives), commit module
      Sync/           # SyncEngine, realtime subscriptions, network monitor
      Utilities/      # Hashtag highlighting, rich text helpers, extensions
      *Manager.swift  # Auth, Echo, Handle, Store, Tier, Profile managers
    Models/           # Note, Section, Handle, Echo, Commit, Module, ShareLink, Insight
    Repositories/     # Data access layer for each model
    ViewModels/       # NotesListViewModel, NoteEditorViewModel, SharedContentViewModel
    Views/
      Auth/           # Sign-in / sign-up
      Editor/         # NoteEditorView, SectionView (iOS UIKit + macOS AppKit representables)
      Intelligence/   # IntelligenceView, InsightCards, Workspace
      Library/        # Profile, loops, share management
      Notes/          # Notes list, note rows, block detail
      Components/     # 26 reusable components (echo config, paywall, FAB, etc.)
      Search/         # Semantic + keyword search
      Settings/       # App settings, subscription management
      Share/          # Shared content viewer
    Resources/        # Assets, Inter font family
supabase/
  migrations/         # PostgreSQL schema migrations
  functions/          # Edge Functions (sync-pull, sync-push, embeddings, search)
```

### Key Patterns

| Pattern | Details |
|---------|---------|
| **Data flow** | `DatabaseManager` -> `Repository` -> `Manager` -> `View` |
| **Storage** | Hot store (SQLite/GRDB) + cold store (file-based `.obx` archives) |
| **Sync** | Offline-first with bidirectional Supabase sync, realtime subscriptions, and conflict resolution |
| **State** | Singleton managers (`EchoManager.shared`, `HandleManager.shared`, etc.) with `@Published` properties |
| **Platform** | Shared SwiftUI codebase with `#if os(iOS)` / `#if os(macOS)` for platform-specific representables |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 16+, macOS 14+) |
| Local DB | [GRDB](https://github.com/groue/GRDB.swift) (SQLite) |
| Backend | [Supabase](https://supabase.com) (PostgreSQL, Auth, Edge Functions, Storage) |
| Payments | [RevenueCat](https://www.revenuecat.com) + StoreKit 2 |
| AI | Claude API (Anthropic) with Gemini fallback for extraction tasks |
| Fonts | Inter (Regular, Medium, SemiBold, Bold, Light) |

## Subscription Tiers

| | Free | Pro | Founding |
|---|------|-----|----------|
| Notes | 50 | Unlimited | Unlimited |
| Cloud Sync | -- | Yes | Yes |
| Version History | -- | Yes | Yes |
| Share Links | -- | Yes | Yes |
| AI Workspace | -- | Yes | Yes |
| Semantic Search | -- | Yes | Yes |
| Daily AI Tokens | 50k | 500k | 500k |

## Setup

### Prerequisites
- Xcode 15+
- iOS 16+ / macOS 14+ deployment targets
- [Supabase CLI](https://supabase.com/docs/guides/cli) (for local backend development)

### Configuration

1. **Clone the repo**
   ```bash
   git clone https://github.com/darko-ops/CodeNameNoodle.git
   cd CodeNameNoodle
   ```

2. **Set up secrets** — Create `Obius-iOS/Obius/Configuration/Secrets.xcconfig` (git-ignored) with:
   ```
   SUPABASE_URL = https://<your-project>.supabase.co
   SUPABASE_ANON_KEY = <your-anon-key>
   CLAUDE_API_KEY = <your-claude-api-key>
   REVENUECAT_API_KEY = <your-revenuecat-key>
   ```

3. **Supabase** — Run migrations and start locally:
   ```bash
   cd supabase
   supabase start
   supabase db push
   ```

4. **Open in Xcode** — Open `Obius-iOS/Obius.xcodeproj`, select your target (iOS or macOS), and build.

### Deep Links

The app registers the `obius://` URL scheme for navigation:
- `obius://note/<id>` — Open a specific note
- `obius://share/<slug>` — Open a shared link

## License

Proprietary. All rights reserved.
