-- Add image and audio content types to sections table
ALTER TABLE public.sections DROP CONSTRAINT IF EXISTS sections_content_type_check;
ALTER TABLE public.sections ADD CONSTRAINT sections_content_type_check
    CHECK (content_type IN ('text', 'checklist', 'code', 'quote', 'image', 'audio'));
