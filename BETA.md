# Obius — Beta

Thanks for helping test Obius. This build is a pre-release — expect rough edges, and please report anything that feels off.

## What is Obius?

Obius is a local-first note-taking app for iOS and macOS. Instead of a single blob of text, every note is a stack of reorderable, collapsible sections. Each section carries a semantic intent — Idea, Question, Task, or Evidence — so your thinking has structure, not just formatting.

Your notes live on-device in a local SQLite database. With a Pro subscription, they sync securely to the cloud; without one, they never leave your device.

## What to try

- **Structured notes** — Create a note, add sections, drag to reorder, indent to nest, and tap the intent pill to change its meaning. Try checklists, code blocks, quotes, images, and audio.
- **Loops (`@handles`)** — Type `@` to create a reusable block (e.g., `@grocery_list`). Link it across notes — edits propagate everywhere.
- **Echoes** — Attach a one-time or recurring reminder to a loop and confirm the notification fires on schedule.
- **Commits** — Open a note's history, browse past snapshots, and restore one. Auto-commit runs daily.
- **Share links** — Generate a public URL for a live note or a frozen commit and open it in a browser.
- **Intelligence** — Try AI title generation, semantic search, and insight cards (leaked-secret detection, cleanup hints, concept linking).
- **Workspace (macOS)** — Chat with AI about a note and let it propose edits you can accept or reject.
- **Locked sections** — Lock a section behind Face ID / Touch ID and verify it stays hidden until you authenticate.
- **Sync** — If you're on Pro, edit the same note on iOS and macOS and confirm changes reconcile without data loss.

## What we especially want feedback on

- Editor feel: drag-to-reorder, indent, intent changes, keyboard behavior
- Sync reliability when switching between online and airplane mode
- Notification delivery for Echoes (including after a reboot)
- Any data loss, crash, or note that fails to open — these are top priority
- AI output quality: are titles, insights, and Workspace suggestions useful or noisy?

## Known limitations in this build

- Some UI polish is incomplete, especially around the paywall and settings
- Conflict resolution during sync may occasionally prefer the newer device's edit without prompting
- AI features require network access and count against your daily token budget (50k Free / 500k Pro)

## How to report bugs

Use TestFlight's built-in feedback (screenshot + note) or reply to the tester email. Please include:

1. Device + OS version (e.g., iPhone 15, iOS 17.4)
2. What you did, what you expected, what happened
3. Whether it's reproducible

## Privacy

Notes stay on-device unless you're on Pro with sync enabled. AI requests send only the content you invoke them on. No analytics are collected in beta beyond crash reports.

Thanks again — your feedback directly shapes 1.0.
