-- Add handle_id column to sections for Handle/Loop support
-- This column links sections to handles (loops)

ALTER TABLE public.sections
  ADD COLUMN IF NOT EXISTS handle_id TEXT;

-- Update color_intent check constraint to include newer intent values
-- Drop old constraint and add new one
ALTER TABLE public.sections DROP CONSTRAINT IF EXISTS sections_color_intent_check;
ALTER TABLE public.sections
  ADD CONSTRAINT sections_color_intent_check
  CHECK (color_intent IS NULL OR color_intent IN ('default', 'important', 'idea', 'task', 'reference', 'evidence'));
