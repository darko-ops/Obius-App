# Analysis: Removing the Profile/Library Tab

## What Exists Today (Tab 3: Library)

The Library tab currently houses five distinct concerns under one roof:

```
LibraryView (Tab 3)
├── User Profile (banner, avatar, name, bio, edit)
├── Settings gear button
├── Active Echoes (recurring reminders, always visible at top)
├── Loops tab (all @Handles: list, create, edit, delete, detail)
└── Commits tab (all snapshots: list, detail, share, comments, hide)
```

This tab is the "identity and audit" layer of the app. The question is what happens when we dismantle it and scatter the pieces.

---

## The Redistribution Plan

### Commits → "Versions" in Per-Note Settings/Details

**What moves:**
- CommitsListView (global, chronological, all notes)
- CommitDetailSheet (metadata card, section preview, comments)
- CommitRowView (spine cards, short IDs, view counts, auto badges)
- Share-from-commit flow
- Context menu (share, copy ID, copy hash, hide)

**What it becomes:**
- A "Versions" section inside a per-note info/details sheet
- Scoped to that single note's commit history
- Accessible from the editor's ellipsis menu or a new note details panel

**Already supported by the data layer:**
- `CommitRepository.getCommits(noteId:)` — per-note queries exist
- `CommitModule.getCommitHistory(noteId:)` — per-note history method exists
- `CommitModule.getCommitChain(from:)` — chain traversal exists
- `CommitModule.diffCommits(oldHash:newHash:)` — diff capability exists
- `CommitModule.restoreCommitById(commitId:)` — restore exists

The infrastructure is ready. Per-note versions are a smaller UI on top of existing queries.

### Loops → Somewhere Else

**Current home:** Library tab, "Loops" segment
- Full list of all @Handles with search
- Create new Loop sheet
- Loop detail sheet (edit content, change intent, delete)
- LoopRowView (spine card with preview)

**Candidate new homes:**
1. **Home/Intelligence tab** — Active Loops summary section
2. **Dedicated Loops floating button or section in Notes list**
3. **Per-note: Loops shown inline where used** (already visible as @tags in editor)

### Active Echoes → Somewhere Else

**Current home:** Always-visible section at top of Library tab
- EchoRowView for each active echo
- Tap opens EchoDetailSheet
- Count badge

**Candidate new homes:**
1. **Home/Intelligence tab** — "Upcoming Echoes" section already exists there
2. **Notification-only** — echoes fire as banners, no persistent list needed

---

## What You Lose: The Developer/Audit Perspective

### 1. The Global Commit Timeline (This Is the Big One)

The current CommitsListView is a `git log` equivalent — every snapshot across every note, newest first, in one scrollable timeline. This gives a developer-type user:

- **Full audit trail at a glance:** "What did I change across all my notes this week?"
- **Cross-note awareness:** See auto-commit patterns, identify which notes are actively evolving
- **The hash/ID system:** `#OBX-A1B2-C3D4`, SHA-256 hashes, `.obx` files — these are developer catnip. Copyable IDs, reproducible hashes, content-addressable storage.
- **View counts on shared commits:** See engagement on shared snapshots

Moving to per-note "Versions" converts `git log` into `git log -- single-file.txt`. You can see one note's history, but you lose the bird's-eye view of your entire knowledge base's evolution.

**Equivalent git analogy:**
```
Before: git log --all --oneline        (global timeline)
After:  git log -- path/to/one/file    (per-file only)
```

You still have history. You lose the timeline.

### 2. The Sharing + Comments Workflow

CommitDetailSheet includes:
- Share button → creates ShareLink → iMessage integration
- Comment thread (CommentThreadView) on shared commits
- View count tracking

Per-note "Versions" could preserve sharing, but the discovery flow changes. Today: browse commits → find interesting one → share. After: open specific note → open versions → find specific snapshot → share. More friction for an already-low-usage feature.

### 3. Cross-Note Commit Statistics

CommitRepository exposes:
- `getCommitStats()` — per-note commit counts
- `getTotalCommitCount()` — total snapshots
- `getLeafCommits()` — most recent snapshot per chain
- `getOrphanedCommits()` — integrity checks

These analytical queries lose their UI surface. No more "I have 147 commits across 23 notes" at a glance. This data exists in SettingsView's data export section already, but it's buried.

### 4. The Auto-Commit Visibility

Auto-commits (orange "Auto" badges) are currently visible in the global timeline. They show the system working for you — daily snapshots happening automatically. Moving to per-note versions makes auto-commits invisible unless you go looking for them in a specific note. The "system is backing up your work" signal disappears.

### 5. Loops Lose Their Dedicated Management Surface

Loops are the core invention of Obius. They currently have a dedicated list with:
- Search across all loops
- Create new loop flow
- Edit content/intent
- Delete

Scattering loops into Intelligence or per-note views risks making them harder to manage in bulk. If you have 20 loops, you need one place to see and manage all 20.

---

## What You Gain

### 1. One Fewer Tab = Simpler Mental Model

```
Before: Notes | Intelligence | Library (3 tabs)
After:  Notes | Home (2 tabs)
```

Two tabs with clear purpose: **Create** (Notes) and **Understand** (Home/Intelligence). No third tab with confused identity trying to be profile + audit + management.

### 2. Versions Feel Native, Not Git-ish

Per-note "Versions" matches user expectations:
- Apple Notes: "Browse All Versions" in the File menu
- Google Docs: "Version history" in the menu
- Notion: "Page history" in the three-dot menu

Users look for version history *inside the document*, not in a separate timeline view. This is more discoverable for 95% of users.

### 3. Commits Stop Competing for Attention

The global commit timeline encourages browsing commits as content. But commits aren't content — they're a safety net. Making them per-note and renaming to "Versions" correctly frames them as infrastructure, not features.

### 4. Loop Management Can Be More Contextual

Instead of managing loops in isolation (Library tab → Loops tab → find loop → edit), loops could be managed where they're used:
- In the editor: tap a @loop inline → edit/view
- In Intelligence: "Active Loops" section with management
- The "Create Loop" flow stays accessible from editor

### 5. Active Echoes Move to Where Insights Live

Echoes are a form of intelligence — temporal awareness. They belong with the Intelligence/Home tab, not with commits and profile banners. The Intelligence tab already has an "Upcoming Echoes" section. Merging active echoes there consolidates the awareness layer.

---

## The Developer/Git Sales Point: Honest Assessment

### What the commit system actually offers devs today:

| Feature | Git Equivalent | Status |
|---------|---------------|--------|
| SHA-256 content hashing | git hash-object | Works, used for dedup |
| Parent hash chaining | git commit --parent | Works, forms DAG |
| Diff between commits | git diff | Works (CommitDiff) |
| Restore to any commit | git checkout <hash> | Works |
| Content-addressable .obx files | git objects | Works |
| Short IDs (OBX-XXXX-XXXX) | git short SHA | Works, copyable |
| Auto-commits on day boundary | git auto-commit hooks | Works |
| Global timeline | git log | Works |
| Per-note history | git log -- file | Works |

### Does removing the Library tab kill this selling point?

**No.** Here's why:

The git-like *infrastructure* remains completely intact regardless of where the UI lives. SHA-256 hashes, parent chains, .obx files, diffs, restore — none of that changes. What changes is the *presentation*.

The real question is: **does a global commit timeline meaningfully differentiate Obius for dev users?**

Argument **for** keeping global timeline:
- Developers think in commit logs. Seeing the full timeline feels familiar and powerful.
- It communicates "this app takes your data seriously" at a glance.
- It's a talking point: "My notes app has content-addressable storage with SHA-256 hashing."

Argument **against**:
- Almost no developer is choosing a notes app because of its commit UI. They choose it for writing speed, Markdown support, or organizational systems.
- Git's power comes from *branching, merging, and collaboration* — none of which Obius implements. The commit system is versioning dressed in git costume. Per-note "Versions" is more honest.
- Developer-targeted notes apps (Obsidian, Logseq) don't have commit UIs. They store files as plain Markdown in actual git repos, which is genuinely more powerful for devs who want git integration.
- The git terminology (commits, hashes, short IDs) creates a false expectation. A developer sees "commit" and expects branching, merging, cherry-picking. When they realize it's linear snapshots only, the terminology feels performative.

### The middle ground: keep the substance, drop the costume

**Per-note "Versions"** preserves everything that actually matters to a developer:
- Full version history per note (git log -- file)
- SHA-256 hashes still visible and copyable
- Diff between versions (could add inline diff view)
- Restore to any version
- Auto-version visibility per note

**What to add to not lose the "power user" signal:**
- In per-note Versions: show hash, parent chain, diff summary
- In Settings > Data: total snapshot count, storage used by .obx files
- Optional: "Export all versions" to .zip for developers who want their data

---

## The Verdict

### What you're actually killing:

| Removed | Impact | Severity |
|---------|--------|----------|
| Global commit timeline | Loses bird's-eye audit view | **Low** — rarely used, not why anyone picks a notes app |
| Social profile (banner/avatar/bio) | Loses social-media pretense | **None** — this is a personal tool, not a social network |
| Dedicated Loop management list | Loops need a new home | **Medium** — need to ensure loops remain first-class |
| Active Echoes in Library | Echoes need a new home | **Low** — Intelligence tab is the natural home |
| Commit sharing + comments | Sharing workflow changes | **Low** — half-built feature with minimal usage |

### What you're gaining:

| Gained | Impact |
|--------|--------|
| Simpler navigation (2 tabs vs 3) | High — reduces cognitive load |
| Versions feel native, not git-cosplay | High — matches user mental model |
| Intelligence tab becomes the true "home" | High — awareness layer consolidates |
| Profile baggage removed | Medium — cleaner identity |

### Net assessment:

**The git selling point was never a real selling point.** It was a developer building a feature they'd personally appreciate, dressed in familiar terminology. No user — not even a developer user — opens a notes app because "it has SHA-256 content-addressable commits." They open it because the writing experience and organizational model click.

The commit infrastructure is excellent engineering and should be preserved as silent auto-versioning. The UI layer (global timeline, profile page) can be safely removed. Per-note "Versions" gives power users everything they need without imposing git-think on everyone else.

**Recommendation: Remove the Library tab.** Redistribute as follows:

```
Commits     → "Versions" in per-note details (keep hash/diff/restore)
Loops       → "Active Loops" section in Home tab + inline management in editor
Echoes      → Merged into Home/Intelligence "Upcoming Echoes" section
Profile     → Settings > Account (name, email, sign out)
Settings    → Gear icon in toolbar (already accessible)
```

The developer who appreciates version history will find it per-note. The developer who wants real git can export their data. And everyone else gets a simpler app.
