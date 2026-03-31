-- Add module_id to notes for project/folder support
ALTER TABLE public.notes
  ADD COLUMN IF NOT EXISTS module_id TEXT;
