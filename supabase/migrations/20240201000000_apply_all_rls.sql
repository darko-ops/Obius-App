-- OBIUS: Apply All Row Level Security Policies
-- Run this in Supabase SQL Editor to set up RLS on your live database
-- This combines all tables: core + sharing

-- ============================================================================
-- 1. CREATE TABLES (if not exists)
-- ============================================================================

-- User Profiles
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    avatar_url TEXT,
    privacy_mode TEXT NOT NULL DEFAULT 'standard' CHECK (privacy_mode IN ('standard', 'private')),
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Notes
CREATE TABLE IF NOT EXISTS public.notes (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    title TEXT,
    ai_title TEXT,
    ai_summary TEXT,
    body TEXT NOT NULL DEFAULT '',
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    color_intent TEXT NOT NULL DEFAULT 'default',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1
);

-- Sections
CREATE TABLE IF NOT EXISTS public.sections (
    id UUID PRIMARY KEY,
    note_id UUID NOT NULL REFERENCES public.notes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL DEFAULT '',
    content_type TEXT NOT NULL DEFAULT 'text',
    parent_section_id UUID REFERENCES public.sections(id) ON DELETE SET NULL,
    order_key TEXT NOT NULL,
    indent_level INTEGER NOT NULL DEFAULT 0,
    is_collapsed BOOLEAN NOT NULL DEFAULT FALSE,
    color_intent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1
);

-- Share Links
CREATE TABLE IF NOT EXISTS public.share_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    share_type TEXT NOT NULL CHECK (share_type IN ('live', 'commit')),
    note_id UUID REFERENCES public.notes(id) ON DELETE CASCADE,
    commit_hash TEXT,
    commit_name TEXT,
    commit_content JSONB,
    is_active BOOLEAN NOT NULL DEFAULT true,
    view_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1
);

-- Comments (Handshakes)
CREATE TABLE IF NOT EXISTS public.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    share_link_id UUID NOT NULL REFERENCES public.share_links(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    user_display_name TEXT,
    parent_comment_id UUID REFERENCES public.comments(id) ON DELETE SET NULL,
    body TEXT NOT NULL,
    sealed_commit_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- ============================================================================
-- 2. ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.share_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. DROP EXISTING POLICIES (clean slate)
-- ============================================================================

-- User Profiles
DROP POLICY IF EXISTS "Users can read own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;

-- Notes
DROP POLICY IF EXISTS "Users can read own notes" ON public.notes;
DROP POLICY IF EXISTS "Users can create own notes" ON public.notes;
DROP POLICY IF EXISTS "Users can update own notes" ON public.notes;
DROP POLICY IF EXISTS "Users can delete own notes" ON public.notes;
DROP POLICY IF EXISTS "Anyone can read shared notes" ON public.notes;

-- Sections
DROP POLICY IF EXISTS "Users can read own sections" ON public.sections;
DROP POLICY IF EXISTS "Users can create own sections" ON public.sections;
DROP POLICY IF EXISTS "Users can update own sections" ON public.sections;
DROP POLICY IF EXISTS "Users can delete own sections" ON public.sections;
DROP POLICY IF EXISTS "Anyone can read shared sections" ON public.sections;

-- Share Links
DROP POLICY IF EXISTS "Users can manage own share links" ON public.share_links;
DROP POLICY IF EXISTS "Anyone can view active share links" ON public.share_links;

-- Comments
DROP POLICY IF EXISTS "Authenticated users can create comments" ON public.comments;
DROP POLICY IF EXISTS "Anyone can view comments" ON public.comments;
DROP POLICY IF EXISTS "Users can manage own comments" ON public.comments;
DROP POLICY IF EXISTS "Users can delete own comments" ON public.comments;

-- ============================================================================
-- 4. USER PROFILES — own data only
-- ============================================================================

CREATE POLICY "Users can read own profile"
    ON public.user_profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.user_profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.user_profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- 5. NOTES — own data + readable via active share links
-- ============================================================================

-- Owner: full CRUD
CREATE POLICY "Users can read own notes"
    ON public.notes FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own notes"
    ON public.notes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notes"
    ON public.notes FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own notes"
    ON public.notes FOR DELETE
    USING (auth.uid() = user_id);

-- Public: anyone can read notes that have an active live share link
CREATE POLICY "Anyone can read shared notes"
    ON public.notes FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.share_links sl
            WHERE sl.note_id = notes.id
              AND sl.share_type = 'live'
              AND sl.is_active = true
              AND sl.deleted_at IS NULL
        )
    );

-- ============================================================================
-- 6. SECTIONS — own data + readable via active share links
-- ============================================================================

-- Owner: full CRUD
CREATE POLICY "Users can read own sections"
    ON public.sections FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own sections"
    ON public.sections FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sections"
    ON public.sections FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own sections"
    ON public.sections FOR DELETE
    USING (auth.uid() = user_id);

-- Public: anyone can read sections belonging to a live-shared note
CREATE POLICY "Anyone can read shared sections"
    ON public.sections FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.share_links sl
            WHERE sl.note_id = sections.note_id
              AND sl.share_type = 'live'
              AND sl.is_active = true
              AND sl.deleted_at IS NULL
        )
    );

-- ============================================================================
-- 7. SHARE LINKS — owners manage, anyone reads active
-- ============================================================================

-- Owner: full control over own share links
CREATE POLICY "Users can manage own share links"
    ON public.share_links FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Public: anyone can look up active share links (needed for get-shared-content)
CREATE POLICY "Anyone can view active share links"
    ON public.share_links FOR SELECT
    USING (is_active = true AND deleted_at IS NULL);

-- ============================================================================
-- 8. COMMENTS — authenticated create, anyone reads, owners manage
-- ============================================================================

-- Any authenticated user can post a comment
CREATE POLICY "Authenticated users can create comments"
    ON public.comments FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Anyone can read non-deleted comments
CREATE POLICY "Anyone can view comments"
    ON public.comments FOR SELECT
    USING (deleted_at IS NULL);

-- Users can edit their own comments
CREATE POLICY "Users can manage own comments"
    ON public.comments FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own comments
CREATE POLICY "Users can delete own comments"
    ON public.comments FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- 9. AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (id, display_name)
    VALUES (NEW.id, NEW.raw_user_meta_data->>'display_name')
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop and recreate trigger to avoid duplicates
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- 10. UPDATED_AT TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_share_links_updated_at ON public.share_links;
CREATE TRIGGER update_share_links_updated_at
    BEFORE UPDATE ON public.share_links
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_comments_updated_at ON public.comments;
CREATE TRIGGER update_comments_updated_at
    BEFORE UPDATE ON public.comments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
