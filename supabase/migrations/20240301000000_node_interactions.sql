-- OBIUS Database Schema
-- Migration: Node Interactions (Handshakes)
-- Version: 3.0.0
--
-- Separates handshake interactions from the comments table into a dedicated
-- table with a unique constraint to prevent duplicate handshakes.

-- ============================================================================
-- NODE INTERACTIONS
-- ============================================================================

CREATE TABLE public.node_interactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    share_link_id UUID NOT NULL REFERENCES public.share_links(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    user_display_name TEXT,
    interaction_type TEXT NOT NULL DEFAULT 'handshake',
    sealed_commit_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Prevent duplicate handshakes per user per share
CREATE UNIQUE INDEX idx_node_interactions_unique
    ON public.node_interactions(share_link_id, user_id, interaction_type);

CREATE INDEX idx_node_interactions_share_link
    ON public.node_interactions(share_link_id);

CREATE INDEX idx_node_interactions_user
    ON public.node_interactions(user_id);

COMMENT ON TABLE public.node_interactions IS 'Interactions (handshakes) on shared content, separate from comments';
COMMENT ON COLUMN public.node_interactions.interaction_type IS 'Type of interaction, currently only handshake';
COMMENT ON COLUMN public.node_interactions.sealed_commit_hash IS 'Commit hash sealed at time of interaction';

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.node_interactions ENABLE ROW LEVEL SECURITY;

-- Authenticated users can create interactions (must match their own user_id)
CREATE POLICY "Authenticated users can create interactions"
    ON public.node_interactions
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Anyone can view interactions
CREATE POLICY "Anyone can view interactions"
    ON public.node_interactions
    FOR SELECT
    USING (true);

-- Users can delete their own interactions
CREATE POLICY "Users can delete own interactions"
    ON public.node_interactions
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- REALTIME
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.node_interactions;
