-- ============================================================================
-- NOTE MEDIA STORAGE BUCKET
-- Stores note images and audio for cross-device sync (iOS + macOS)
-- Files are stored as: {user_id}/{sha256_hash}
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'note-media',
    'note-media',
    false,
    20971520,  -- 20MB max per file (images + audio)
    ARRAY['image/jpeg', 'image/png', 'image/heic', 'audio/mp4', 'audio/mpeg', 'audio/m4a']
)
ON CONFLICT (id) DO NOTHING;

-- RLS policies: users can only access their own media files
-- Path format: {user_id}/{hash}

CREATE POLICY "Users can upload their own note media"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'note-media'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);

CREATE POLICY "Users can update their own note media"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'note-media'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);

CREATE POLICY "Users can read their own note media"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'note-media'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);

CREATE POLICY "Users can delete their own note media"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'note-media'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);
