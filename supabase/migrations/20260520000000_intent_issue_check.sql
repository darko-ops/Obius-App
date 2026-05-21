-- Allow the new 'issue' (Red) intent value on the server.
--
-- The iOS client added a 5th intent case `issue` (rendered Red, user-facing
-- label "Issue") in May 2026. The server's CHECK constraints on
-- sections.color_intent and notes.color_intent reject this new value,
-- which makes sync-push return success=false with no conflict info — the
-- client interprets the response as "still pending" and retries the same
-- op forever. See SyncOperationLogger.swift writing `intent.legacyValue`
-- into `color_intent`.
--
-- This migration:
--   1. Drops the existing CHECK constraints on sections.color_intent and
--      notes.color_intent (if present).
--   2. Recreates them with the full set of legacy + current intent values:
--      'default', 'important', 'idea', 'task', 'question', 'issue',
--      'evidence', 'reference'.
--
-- handles.intent intentionally has no CHECK constraint, so no change there.
--
-- Idempotent — safe to re-run.

ALTER TABLE public.sections DROP CONSTRAINT IF EXISTS sections_color_intent_check;
ALTER TABLE public.sections
  ADD CONSTRAINT sections_color_intent_check
  CHECK (
    color_intent IS NULL
    OR color_intent IN ('default', 'important', 'idea', 'task', 'question', 'issue', 'evidence', 'reference')
  );

ALTER TABLE public.notes DROP CONSTRAINT IF EXISTS notes_color_intent_check;
ALTER TABLE public.notes
  ADD CONSTRAINT notes_color_intent_check
  CHECK (
    color_intent IS NULL
    OR color_intent IN ('default', 'important', 'idea', 'task', 'question', 'issue', 'evidence', 'reference')
  );
