-- Create handles table for cloud sync of handle loops
CREATE TABLE IF NOT EXISTS public.handles (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    intent TEXT DEFAULT 'idea',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1,
    last_modified_by TEXT
);

-- Indexes
CREATE INDEX idx_handles_user_id ON public.handles(user_id);
CREATE INDEX idx_handles_name ON public.handles(user_id, name) WHERE deleted_at IS NULL;

-- Enable RLS
ALTER TABLE public.handles ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Users can read own handles"
    ON public.handles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own handles"
    ON public.handles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own handles"
    ON public.handles FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own handles"
    ON public.handles FOR DELETE
    USING (auth.uid() = user_id);
