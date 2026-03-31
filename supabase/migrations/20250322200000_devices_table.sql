-- Create devices table for multi-device sync
-- Used by sync-pull/sync-push to validate device ownership

CREATE TABLE IF NOT EXISTS public.devices (
    id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_name TEXT,
    platform TEXT NOT NULL DEFAULT 'ios',
    app_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for user lookups
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON public.devices (user_id);

-- RLS policies
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

-- Users can only see/manage their own devices
CREATE POLICY "Users can view own devices"
    ON public.devices FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own devices"
    ON public.devices FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own devices"
    ON public.devices FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own devices"
    ON public.devices FOR DELETE
    USING (auth.uid() = user_id);

-- Service role needs full access (for edge functions)
CREATE POLICY "Service role full access on devices"
    ON public.devices FOR ALL
    USING (auth.role() = 'service_role');
