-- OBIUS Seed Data for Development
-- Run after migrations to set up test data

-- Note: This requires a test user to exist in auth.users
-- Create one via Supabase Dashboard or Auth API first

-- Example seed data (uncomment and modify with real user ID)

/*
-- Insert test user profile
INSERT INTO public.user_profiles (id, display_name, privacy_mode)
VALUES
    ('YOUR-USER-UUID-HERE', 'Test User', 'standard');

-- Insert test device
INSERT INTO public.devices (id, user_id, device_name, platform, app_version)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'YOUR-USER-UUID-HERE', 'iPhone 15', 'ios', '1.0.0');

-- Insert test notes
INSERT INTO public.notes (id, user_id, title, color_intent, created_at, updated_at)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'YOUR-USER-UUID-HERE', 'Welcome to Obius', 'idea', NOW(), NOW()),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'YOUR-USER-UUID-HERE', 'Project Ideas', 'task', NOW(), NOW()),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'YOUR-USER-UUID-HERE', NULL, 'default', NOW(), NOW());

-- Insert test sections for first note
INSERT INTO public.sections (id, note_id, user_id, content, order_key, indent_level, created_at, updated_at)
VALUES
    ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'YOUR-USER-UUID-HERE',
     'Obius is a local-first notes app where ideas live as structured, searchable sections.', 'A', 0, NOW(), NOW()),
    ('22222222-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'YOUR-USER-UUID-HERE',
     'Key features:', 'B', 0, NOW(), NOW()),
    ('33333333-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'YOUR-USER-UUID-HERE',
     'Section-first mental model', 'C', 1, NOW(), NOW()),
    ('44444444-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'YOUR-USER-UUID-HERE',
     'Semantic search with AI', 'D', 1, NOW(), NOW()),
    ('55555555-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'YOUR-USER-UUID-HERE',
     'Local-first with cloud sync', 'E', 1, NOW(), NOW());

-- Insert test sections for second note
INSERT INTO public.sections (id, note_id, user_id, content, order_key, indent_level, color_intent, created_at, updated_at)
VALUES
    ('11111111-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'YOUR-USER-UUID-HERE',
     'Mobile app improvements', 'A', 0, 'important', NOW(), NOW()),
    ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'YOUR-USER-UUID-HERE',
     'Backend optimization', 'B', 0, NULL, NOW(), NOW()),
    ('33333333-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'YOUR-USER-UUID-HERE',
     'User research findings', 'C', 0, 'reference', NOW(), NOW());
*/

-- Utility function to generate test data
CREATE OR REPLACE FUNCTION generate_test_data(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_note_id UUID;
    v_device_id UUID := uuid_generate_v4();
BEGIN
    -- Create device
    INSERT INTO public.devices (id, user_id, device_name, platform, app_version)
    VALUES (v_device_id, p_user_id, 'Test Device', 'ios', '1.0.0');

    -- Create welcome note
    v_note_id := uuid_generate_v4();
    INSERT INTO public.notes (id, user_id, title, color_intent, created_at, updated_at)
    VALUES (v_note_id, p_user_id, 'Welcome to Obius', 'idea', NOW(), NOW());

    INSERT INTO public.sections (id, note_id, user_id, content, order_key, indent_level, created_at, updated_at)
    VALUES
        (uuid_generate_v4(), v_note_id, p_user_id, 'Obius is a local-first notes app.', 'A', 0, NOW(), NOW()),
        (uuid_generate_v4(), v_note_id, p_user_id, 'Your notes are always available offline.', 'B', 0, NOW(), NOW()),
        (uuid_generate_v4(), v_note_id, p_user_id, 'AI helps you find and organize ideas.', 'C', 0, NOW(), NOW());

    -- Create sample note
    v_note_id := uuid_generate_v4();
    INSERT INTO public.notes (id, user_id, title, color_intent, is_pinned, created_at, updated_at)
    VALUES (v_note_id, p_user_id, 'Quick Ideas', 'task', TRUE, NOW(), NOW());

    INSERT INTO public.sections (id, note_id, user_id, content, order_key, indent_level, created_at, updated_at)
    VALUES
        (uuid_generate_v4(), v_note_id, p_user_id, 'Remember to explore the app', 'A', 0, NOW(), NOW());
END;
$$;

-- Usage: SELECT generate_test_data('your-user-uuid-here');
