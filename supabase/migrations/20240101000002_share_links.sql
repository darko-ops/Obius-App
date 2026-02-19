-- OBIUS Database Schema
-- Migration: Share Links & Comments
-- Version: 2.0.0

-- ============================================================================
-- SHARE LINKS
-- ============================================================================

CREATE TABLE public.share_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    share_type TEXT NOT NULL CHECK (share_type IN ('live', 'commit')),

    -- Content references
    note_id UUID REFERENCES public.notes(id) ON DELETE CASCADE,
    commit_hash TEXT,
    commit_name TEXT,
    commit_content JSONB,  -- Stores .obx content for commit shares

    -- State
    is_active BOOLEAN NOT NULL DEFAULT true,
    view_count INTEGER NOT NULL DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,

    -- Sync
    version INTEGER NOT NULL DEFAULT 1,

    -- Constraints
    CONSTRAINT share_links_live_requires_note CHECK (
        share_type != 'live' OR note_id IS NOT NULL
    ),
    CONSTRAINT share_links_commit_requires_hash CHECK (
        share_type != 'commit' OR commit_hash IS NOT NULL
    )
);

CREATE UNIQUE INDEX idx_share_links_slug ON public.share_links(slug);
CREATE INDEX idx_share_links_user ON public.share_links(user_id);
CREATE INDEX idx_share_links_note ON public.share_links(note_id) WHERE note_id IS NOT NULL;
CREATE INDEX idx_share_links_commit ON public.share_links(commit_hash) WHERE commit_hash IS NOT NULL;
CREATE INDEX idx_share_links_active ON public.share_links(is_active) WHERE is_active = true AND deleted_at IS NULL;

COMMENT ON TABLE public.share_links IS 'Shareable links to notes (live) or commits (snapshot)';
COMMENT ON COLUMN public.share_links.slug IS '8-char base62 URL identifier';
COMMENT ON COLUMN public.share_links.commit_content IS 'Full .obx content stored as JSONB for commit shares';

-- ============================================================================
-- COMMENTS (Handshakes)
-- ============================================================================

CREATE TABLE public.comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    share_link_id UUID NOT NULL REFERENCES public.share_links(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    user_display_name TEXT,
    parent_comment_id UUID REFERENCES public.comments(id) ON DELETE SET NULL,
    body TEXT NOT NULL,

    -- For commit shares: sealed hash after this comment
    sealed_commit_hash TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_comments_share_link ON public.comments(share_link_id);
CREATE INDEX idx_comments_user ON public.comments(user_id);
CREATE INDEX idx_comments_parent ON public.comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;

COMMENT ON TABLE public.comments IS 'Comments (Handshakes) on shared content';
COMMENT ON COLUMN public.comments.sealed_commit_hash IS 'SHA-256 hash of original content + all comments up to this point';

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.share_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- Share Links: owners manage their own; anyone can read active shares
CREATE POLICY "Users can manage own share links"
    ON public.share_links
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Anyone can view active share links"
    ON public.share_links
    FOR SELECT
    USING (is_active = true AND deleted_at IS NULL);

-- Comments: authenticated users can create; anyone can read; users manage own
CREATE POLICY "Authenticated users can create comments"
    ON public.comments
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Anyone can view comments"
    ON public.comments
    FOR SELECT
    USING (deleted_at IS NULL);

CREATE POLICY "Users can manage own comments"
    ON public.comments
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own comments"
    ON public.comments
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_share_links_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER share_links_updated_at
    BEFORE UPDATE ON public.share_links
    FOR EACH ROW EXECUTE FUNCTION update_share_links_updated_at();

CREATE TRIGGER comments_updated_at
    BEFORE UPDATE ON public.comments
    FOR EACH ROW EXECUTE FUNCTION update_share_links_updated_at();

-- ============================================================================
-- REALTIME
-- ============================================================================

-- Enable Realtime for live share updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.share_links;
ALTER PUBLICATION supabase_realtime ADD TABLE public.comments;
