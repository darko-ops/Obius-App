-- OBIUS Database Schema
-- Migration: Initial Setup
-- Version: 1.0.0

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ============================================================================
-- USER PROFILES
-- ============================================================================

CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    avatar_url TEXT,
    privacy_mode TEXT NOT NULL DEFAULT 'standard' CHECK (privacy_mode IN ('standard', 'private')),
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.user_profiles IS 'Extended user profile information';
COMMENT ON COLUMN public.user_profiles.privacy_mode IS 'standard = sync + AI, private = local only';

-- ============================================================================
-- DEVICES (for sync tracking)
-- ============================================================================

CREATE TABLE public.devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    device_name TEXT,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    app_version TEXT,
    os_version TEXT,
    push_token TEXT,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_devices_user ON public.devices(user_id);
CREATE INDEX idx_devices_last_sync ON public.devices(user_id, last_sync_at);

COMMENT ON TABLE public.devices IS 'Registered devices for sync';

-- ============================================================================
-- NOTES
-- ============================================================================

CREATE TABLE public.notes (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,

    -- Content
    title TEXT,
    ai_title TEXT,
    ai_summary TEXT,

    -- Metadata
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    color_intent TEXT NOT NULL DEFAULT 'default'
        CHECK (color_intent IN ('default', 'important', 'idea', 'task', 'reference')),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    deleted_at TIMESTAMPTZ,

    -- Sync versioning
    version INTEGER NOT NULL DEFAULT 1,
    last_modified_by UUID REFERENCES public.devices(id)
);

CREATE INDEX idx_notes_user ON public.notes(user_id);
CREATE INDEX idx_notes_user_updated ON public.notes(user_id, updated_at DESC);
CREATE INDEX idx_notes_user_deleted ON public.notes(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_notes_sync ON public.notes(user_id, version);

COMMENT ON TABLE public.notes IS 'User notes - containers for sections';

-- ============================================================================
-- SECTIONS (atomic content units)
-- ============================================================================

CREATE TABLE public.sections (
    id UUID PRIMARY KEY,
    note_id UUID NOT NULL REFERENCES public.notes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,

    -- Content
    content TEXT NOT NULL DEFAULT '',
    content_type TEXT NOT NULL DEFAULT 'text'
        CHECK (content_type IN ('text', 'checklist', 'code', 'quote')),

    -- Hierarchy & ordering
    parent_section_id UUID REFERENCES public.sections(id) ON DELETE SET NULL,
    order_key TEXT NOT NULL,
    indent_level INTEGER NOT NULL DEFAULT 0 CHECK (indent_level >= 0 AND indent_level <= 10),

    -- UI state
    is_collapsed BOOLEAN NOT NULL DEFAULT FALSE,
    color_intent TEXT CHECK (color_intent IN ('default', 'important', 'idea', 'task', 'reference')),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    deleted_at TIMESTAMPTZ,

    -- Sync versioning
    version INTEGER NOT NULL DEFAULT 1,
    last_modified_by UUID REFERENCES public.devices(id),

    -- AI / Semantic search
    embedding vector(1536),
    embedding_model TEXT,
    embedding_updated_at TIMESTAMPTZ
);

CREATE INDEX idx_sections_note ON public.sections(note_id);
CREATE INDEX idx_sections_user ON public.sections(user_id);
CREATE INDEX idx_sections_order ON public.sections(note_id, order_key);
CREATE INDEX idx_sections_user_updated ON public.sections(user_id, updated_at DESC);
CREATE INDEX idx_sections_sync ON public.sections(user_id, version);
CREATE INDEX idx_sections_parent ON public.sections(parent_section_id) WHERE parent_section_id IS NOT NULL;

-- Vector similarity index for semantic search
CREATE INDEX idx_sections_embedding ON public.sections
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

COMMENT ON TABLE public.sections IS 'Section content - atomic units within notes';
COMMENT ON COLUMN public.sections.embedding IS 'OpenAI text-embedding-3-small vector (1536 dimensions)';

-- ============================================================================
-- SYNC CHANGELOG (for tracking changes across devices)
-- ============================================================================

CREATE TABLE public.sync_changelog (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,

    -- Change info
    entity_type TEXT NOT NULL CHECK (entity_type IN ('note', 'section')),
    entity_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'delete')),

    -- Change details
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    previous_version INTEGER,
    new_version INTEGER,

    -- Timestamps
    client_timestamp TIMESTAMPTZ NOT NULL,
    server_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_changelog_user ON public.sync_changelog(user_id);
CREATE INDEX idx_changelog_user_time ON public.sync_changelog(user_id, server_timestamp DESC);
CREATE INDEX idx_changelog_entity ON public.sync_changelog(entity_type, entity_id);
CREATE INDEX idx_changelog_device ON public.sync_changelog(device_id, server_timestamp DESC);

COMMENT ON TABLE public.sync_changelog IS 'Append-only log of all changes for sync';

-- ============================================================================
-- SYNC METADATA (per-device sync state)
-- ============================================================================

CREATE TABLE public.sync_state (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,

    last_sync_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_changelog_id BIGINT REFERENCES public.sync_changelog(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id, device_id)
);

CREATE INDEX idx_sync_state_device ON public.sync_state(device_id);

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_devices_updated_at
    BEFORE UPDATE ON public.devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sync_state_updated_at
    BEFORE UPDATE ON public.sync_state
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to auto-create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (id, display_name)
    VALUES (NEW.id, NEW.raw_user_meta_data->>'display_name');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on user signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- SEMANTIC SEARCH FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION search_sections_semantic(
    query_embedding vector(1536),
    match_threshold float DEFAULT 0.7,
    match_count int DEFAULT 20,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS TABLE (
    section_id uuid,
    note_id uuid,
    content text,
    similarity float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id as section_id,
        s.note_id,
        s.content,
        1 - (s.embedding <=> query_embedding) as similarity
    FROM public.sections s
    WHERE s.user_id = p_user_id
        AND s.deleted_at IS NULL
        AND s.embedding IS NOT NULL
        AND 1 - (s.embedding <=> query_embedding) > match_threshold
    ORDER BY s.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

COMMENT ON FUNCTION search_sections_semantic IS 'Semantic search using vector similarity';

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get changes since timestamp for sync
CREATE OR REPLACE FUNCTION get_changes_since(
    p_user_id uuid,
    p_since_timestamp timestamptz,
    p_device_id uuid DEFAULT NULL
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    operation text,
    data jsonb,
    server_timestamp timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        cl.entity_type,
        cl.entity_id,
        cl.operation,
        cl.payload as data,
        cl.server_timestamp
    FROM public.sync_changelog cl
    WHERE cl.user_id = p_user_id
        AND cl.server_timestamp > p_since_timestamp
        AND (p_device_id IS NULL OR cl.device_id != p_device_id)
    ORDER BY cl.server_timestamp ASC;
END;
$$;

-- Record a sync operation
CREATE OR REPLACE FUNCTION record_sync_operation(
    p_user_id uuid,
    p_device_id uuid,
    p_entity_type text,
    p_entity_id uuid,
    p_operation text,
    p_payload jsonb,
    p_client_timestamp timestamptz,
    p_previous_version integer DEFAULT NULL,
    p_new_version integer DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_changelog_id bigint;
BEGIN
    INSERT INTO public.sync_changelog (
        user_id,
        device_id,
        entity_type,
        entity_id,
        operation,
        payload,
        client_timestamp,
        previous_version,
        new_version
    ) VALUES (
        p_user_id,
        p_device_id,
        p_entity_type,
        p_entity_id,
        p_operation,
        p_payload,
        p_client_timestamp,
        p_previous_version,
        p_new_version
    )
    RETURNING id INTO v_changelog_id;

    RETURN v_changelog_id;
END;
$$;
