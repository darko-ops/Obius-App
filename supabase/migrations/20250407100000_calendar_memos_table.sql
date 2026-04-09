-- ============================================================================
-- CALENDAR MEMOS TABLE
-- Stores per-day memo text for the calendar view, synced across devices
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.calendar_memos (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    date_key TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1,
    last_modified_by TEXT
);

-- Each user can have one memo per day
CREATE UNIQUE INDEX idx_calendar_memos_user_date ON public.calendar_memos(user_id, date_key) WHERE deleted_at IS NULL;
CREATE INDEX idx_calendar_memos_user_id ON public.calendar_memos(user_id);

-- Enable RLS
ALTER TABLE public.calendar_memos ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Users can read own calendar memos"
    ON public.calendar_memos FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own calendar memos"
    ON public.calendar_memos FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own calendar memos"
    ON public.calendar_memos FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own calendar memos"
    ON public.calendar_memos FOR DELETE
    USING (auth.uid() = user_id);

-- Update sync_changelog entity_type constraint to include 'calendar_memo'
ALTER TABLE public.sync_changelog
    DROP CONSTRAINT IF EXISTS sync_changelog_entity_type_check;

ALTER TABLE public.sync_changelog
    ADD CONSTRAINT sync_changelog_entity_type_check
    CHECK (entity_type IN ('note', 'section', 'echo', 'handle', 'calendar_memo'));
