-- Add group_name column to notes for block grouping
ALTER TABLE public.notes ADD COLUMN IF NOT EXISTS group_name TEXT;
