-- ============================================================================
-- FIX: Profile images RLS policies
-- Use path_tokens instead of storage.foldername for proper path matching
-- ============================================================================

-- Drop the old policies
DROP POLICY IF EXISTS "Users can upload their own profile images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own profile images" ON storage.objects;
DROP POLICY IF EXISTS "Users can read their own profile images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own profile images" ON storage.objects;

-- Recreate with correct path matching
-- storage.objects.name contains the full path like "C38F57CB-.../avatar.jpg"
-- We split on '/' and check the first segment matches the user's ID

CREATE POLICY "Users can upload their own profile images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'profile-images'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);

CREATE POLICY "Users can update their own profile images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'profile-images'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);

CREATE POLICY "Users can read their own profile images"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'profile-images'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);

CREATE POLICY "Users can delete their own profile images"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'profile-images'
    AND lower(auth.uid()::text) = lower((string_to_array(name, '/'))[1])
);
