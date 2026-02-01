-- OBIUS Row Level Security Policies
-- Migration: RLS Setup
-- Version: 1.0.0

-- ============================================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_changelog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- USER PROFILES POLICIES
-- ============================================================================

-- Users can read their own profile
CREATE POLICY "Users can read own profile"
    ON public.user_profiles
    FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON public.user_profiles
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Profile is created automatically via trigger, but allow insert for edge cases
CREATE POLICY "Users can insert own profile"
    ON public.user_profiles
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- DEVICES POLICIES
-- ============================================================================

-- Users can read their own devices
CREATE POLICY "Users can read own devices"
    ON public.devices
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can create devices for themselves
CREATE POLICY "Users can create own devices"
    ON public.devices
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own devices
CREATE POLICY "Users can update own devices"
    ON public.devices
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own devices
CREATE POLICY "Users can delete own devices"
    ON public.devices
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- NOTES POLICIES
-- ============================================================================

-- Users can read their own notes
CREATE POLICY "Users can read own notes"
    ON public.notes
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can create notes for themselves
CREATE POLICY "Users can create own notes"
    ON public.notes
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own notes
CREATE POLICY "Users can update own notes"
    ON public.notes
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own notes
CREATE POLICY "Users can delete own notes"
    ON public.notes
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- SECTIONS POLICIES
-- ============================================================================

-- Users can read their own sections
CREATE POLICY "Users can read own sections"
    ON public.sections
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can create sections for themselves
CREATE POLICY "Users can create own sections"
    ON public.sections
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own sections
CREATE POLICY "Users can update own sections"
    ON public.sections
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own sections
CREATE POLICY "Users can delete own sections"
    ON public.sections
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- SYNC CHANGELOG POLICIES
-- ============================================================================

-- Users can read their own changelog entries
CREATE POLICY "Users can read own changelog"
    ON public.sync_changelog
    FOR SELECT
    USING (auth.uid() = user_id);

-- Changelog entries are created via functions (SECURITY DEFINER)
-- But allow direct insert for edge cases
CREATE POLICY "Users can insert own changelog"
    ON public.sync_changelog
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- SYNC STATE POLICIES
-- ============================================================================

-- Users can read their own sync state
CREATE POLICY "Users can read own sync state"
    ON public.sync_state
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can create sync state for themselves
CREATE POLICY "Users can create own sync state"
    ON public.sync_state
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own sync state
CREATE POLICY "Users can update own sync state"
    ON public.sync_state
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own sync state
CREATE POLICY "Users can delete own sync state"
    ON public.sync_state
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- SERVICE ROLE BYPASS (for Edge Functions)
-- ============================================================================

-- Note: Edge Functions using service_role key bypass RLS automatically
-- These policies ensure authenticated users can only access their own data
-- while service role can access all data for sync operations
