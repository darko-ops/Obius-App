-- Create echoes table for cloud sync of echo reminders
CREATE TABLE IF NOT EXISTS public.echoes (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    handle_id TEXT NOT NULL,
    is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
    intervals_json TEXT,
    fire_date BIGINT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    next_fire_date BIGINT,
    is_alerted BOOLEAN NOT NULL DEFAULT FALSE,
    last_acknowledged_at BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1,
    last_modified_by TEXT
);

-- Indexes
CREATE INDEX idx_echoes_user_id ON public.echoes(user_id);
CREATE INDEX idx_echoes_handle_id ON public.echoes(handle_id);
CREATE INDEX idx_echoes_active ON public.echoes(user_id, is_active) WHERE deleted_at IS NULL;

-- Enable RLS
ALTER TABLE public.echoes ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Users can read own echoes"
    ON public.echoes FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own echoes"
    ON public.echoes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own echoes"
    ON public.echoes FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own echoes"
    ON public.echoes FOR DELETE
    USING (auth.uid() = user_id);

-- Update sync_changelog entity_type constraint to include 'echo'
ALTER TABLE public.sync_changelog
    DROP CONSTRAINT IF EXISTS sync_changelog_entity_type_check;

ALTER TABLE public.sync_changelog
    ADD CONSTRAINT sync_changelog_entity_type_check
    CHECK (entity_type IN ('note', 'section', 'echo', 'handle'));
