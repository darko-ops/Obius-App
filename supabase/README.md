# OBIUS Supabase Backend

This directory contains the Supabase configuration, database migrations, and Edge Functions for OBIUS.

## Setup

### 1. Install Supabase CLI

```bash
# macOS
brew install supabase/tap/supabase

# npm
npm install -g supabase

# Or download from https://github.com/supabase/cli/releases
```

### 2. Login to Supabase

```bash
supabase login
```

### 3. Link to your project

```bash
# Create a new project at https://supabase.com/dashboard
# Then link it:
supabase link --project-ref YOUR_PROJECT_REF
```

### 4. Run migrations

```bash
supabase db push
```

### 5. Deploy Edge Functions

```bash
# Deploy all functions
supabase functions deploy

# Or deploy individually
supabase functions deploy sync-pull
supabase functions deploy sync-push
supabase functions deploy generate-embedding
supabase functions deploy generate-summary
supabase functions deploy semantic-search
```

### 6. Set environment variables

In your Supabase Dashboard → Project Settings → Edge Functions:

```
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

## Directory Structure

```
supabase/
├── config.toml                 # Supabase configuration
├── migrations/
│   ├── 20240101000000_initial_schema.sql   # Tables, indexes, functions
│   └── 20240101000001_rls_policies.sql     # Row Level Security
├── functions/
│   ├── _shared/                # Shared code
│   │   ├── types.ts            # TypeScript types
│   │   ├── supabase-client.ts  # Client helpers
│   │   ├── openai-client.ts    # OpenAI API
│   │   └── anthropic-client.ts # Claude API
│   ├── sync-pull/              # Pull changes from server
│   ├── sync-push/              # Push changes to server
│   ├── generate-embedding/     # Create section embeddings
│   ├── generate-summary/       # AI title/summary generation
│   └── semantic-search/        # Vector similarity search
├── seed.sql                    # Test data
└── README.md                   # This file
```

## Database Schema

### Tables

- **user_profiles** - Extended user info (privacy mode, settings)
- **devices** - Registered devices for sync
- **notes** - Note containers
- **sections** - Atomic content units with embeddings
- **sync_changelog** - Append-only change log
- **sync_state** - Per-device sync cursor

### Key Features

- **pgvector** for semantic search (1536-dim embeddings)
- **Row Level Security** - Users can only access their own data
- **Soft deletes** - `deleted_at` timestamp instead of hard delete
- **Version tracking** - For conflict resolution

## Edge Functions

### Sync Pull
`POST /functions/v1/sync-pull`

Fetches changes since last sync.

```json
{
  "device_id": "uuid",
  "last_sync_timestamp": "2024-01-01T00:00:00Z"
}
```

### Sync Push
`POST /functions/v1/sync-push`

Pushes local changes to server.

```json
{
  "device_id": "uuid",
  "operations": [
    {
      "operation_id": "uuid",
      "entity_type": "note",
      "entity_id": "uuid",
      "operation": "create",
      "payload": { ... },
      "client_timestamp": "...",
      "client_version": 1
    }
  ]
}
```

### Generate Embedding
`POST /functions/v1/generate-embedding`

Creates embeddings for sections.

```json
{
  "section_id": "uuid",
  "content": "optional override"
}
```

### Generate Summary
`POST /functions/v1/generate-summary`

Creates AI title and summary for a note.

```json
{
  "note_id": "uuid"
}
```

### Semantic Search
`POST /functions/v1/semantic-search`

Searches sections by meaning.

```json
{
  "query": "search text",
  "limit": 20,
  "threshold": 0.7
}
```

## Local Development

```bash
# Start local Supabase
supabase start

# Run a specific function locally
supabase functions serve sync-pull --env-file .env.local

# View logs
supabase functions logs sync-pull
```

## Testing

```sql
-- Generate test data for a user
SELECT generate_test_data('your-user-uuid');
```
