-- Create sync_changelog table for tracking changes across devices
-- Required by sync-pull and sync-push edge functions

CREATE TABLE IF NOT EXISTS public.sync_changelog (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,

    -- Change info
    entity_type TEXT NOT NULL CHECK (entity_type IN ('note', 'section')),
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'delete')),

    -- Change details
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    previous_version INTEGER,
    new_version INTEGER,

    -- Timestamps
    client_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    server_timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_changelog_user ON public.sync_changelog(user_id);
CREATE INDEX IF NOT EXISTS idx_changelog_user_time ON public.sync_changelog(user_id, server_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_entity ON public.sync_changelog(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_changelog_device ON public.sync_changelog(device_id, server_timestamp DESC);

-- RLS policies
ALTER TABLE public.sync_changelog ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own changelog"
    ON public.sync_changelog FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own changelog"
    ON public.sync_changelog FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role full access on sync_changelog"
    ON public.sync_changelog FOR ALL
    USING (auth.role() = 'service_role');
