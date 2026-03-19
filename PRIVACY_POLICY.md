# Privacy Policy

**Obius**
**Effective Date: March 19, 2026**

## Introduction

Obius ("we", "our", or "the app") is a local-first notes application. This Privacy Policy explains how we collect, use, and protect your information when you use Obius.

## Data We Collect

### Account Information

When you create an account, we collect:

- Email address
- Password (stored securely via Supabase Auth)
- Display name (optional)

### Notes and Content

- Note titles, text, checklists, code snippets, and other content you create
- Section structure and organization metadata (ordering, nesting, collapse state)
- Color and category labels you assign to notes

### Device Information

When you enable sync, we collect:

- Device name and platform (iOS, macOS, web)
- App version and OS version
- Push notification token (if notifications are enabled)

### AI Usage Data

When you use AI-powered features (summaries, semantic search), we log:

- The type of action performed
- Token counts (input and output)
- The model used
- Timestamp

We do **not** store the content of your AI requests or responses in our usage logs.

### Sharing and Collaboration Data

When you share a note, we store:

- The shared content snapshot or live link reference
- View counts on shared links
- Comments and interactions from collaborators

## How We Use Your Data

We use your data to:

- Provide core app functionality (creating, editing, and organizing notes)
- Sync notes across your devices when sync is enabled
- Generate AI-powered summaries and enable semantic search
- Deliver shared notes to your intended recipients
- Track AI usage for service limits and cost management

We do **not** sell, rent, or share your personal data with third parties for advertising or marketing purposes.

## Local-First Architecture

Obius is designed with a local-first architecture:

- **All notes are stored locally on your device first** using an on-device database
- Notes are only transmitted to our servers when you have sync enabled
- The app works fully offline without any data leaving your device

## Privacy Mode

Obius offers a **Privacy Mode** setting:

- **Standard mode**: Notes sync across devices and AI features are available
- **Private mode**: Notes remain exclusively on your device. No data is synced to our servers and AI features that require server processing are disabled.

You can switch between modes at any time in your account settings.

## Data Storage and Security

- Local data is stored in an on-device SQLite database
- Authentication tokens are stored in the device Keychain
- Remote data is stored in a Supabase-hosted PostgreSQL database with row-level security, ensuring users can only access their own data
- All network communication uses HTTPS/TLS encryption

## Third-Party Services

We use the following third-party services to operate the app:

| Service | Purpose | Data Shared |
|---------|---------|-------------|
| Supabase | Authentication, database, sync | Account info, synced notes |
| OpenAI | Generating text embeddings for semantic search | Note content (for embedding generation) |
| Anthropic | AI-powered summaries and text generation | Note content (for summary generation) |

These services process your data in accordance with their own privacy policies. Note content sent to AI providers is used solely for generating responses and is not used to train their models (per their API terms of service).

## Data Retention

- Your local data persists on your device until you delete it or uninstall the app
- Synced data is retained on our servers while your account is active
- Deleted notes are soft-deleted and permanently purged after 30 days
- You can request full deletion of your account and associated data at any time

## Your Rights

You have the right to:

- **Access** your data at any time through the app
- **Export** your notes from the app
- **Delete** your account and all associated server-side data
- **Opt out** of cloud sync by enabling Privacy Mode
- **Withdraw consent** for AI features by disabling them in settings

## Children's Privacy

Obius is not directed at children under the age of 13. We do not knowingly collect personal information from children under 13. If you believe a child has provided us with personal data, please contact us so we can delete it.

## Changes to This Policy

We may update this Privacy Policy from time to time. We will notify you of significant changes through the app or via email. Continued use of the app after changes constitutes acceptance of the updated policy.

## Contact Us

If you have questions about this Privacy Policy or your data, please contact us at:

**Email**: privacy@obius.app
