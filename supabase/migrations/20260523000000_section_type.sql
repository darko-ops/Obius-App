-- Add `section_type` column to sections so the share/preview pipeline can
-- distinguish between "fold" nodes (styled with intent rail + background)
-- and "line" sections (plain text rendered between nodes).
--
-- The iOS client stores this distinction locally (Section.sectionType, fold
-- vs. line) but never pushed it to Supabase, so shared-page previews
-- rendered every section with fold styling — line sections appeared as
-- boxed nodes instead of plain text "between" the nodes.
--
-- Default is 'fold' so existing rows remain visually consistent until the
-- client re-syncs them with the correct value.
--
-- Idempotent — safe to re-run.

ALTER TABLE public.sections
  ADD COLUMN IF NOT EXISTS section_type TEXT NOT NULL DEFAULT 'fold';

ALTER TABLE public.sections DROP CONSTRAINT IF EXISTS sections_section_type_check;
ALTER TABLE public.sections
  ADD CONSTRAINT sections_section_type_check
  CHECK (section_type IN ('fold', 'line'));
