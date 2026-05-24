-- Force byte-wise ("C" locale) ordering on sections.order_key so server-side
-- ORDER BY matches the iOS client's SQLite BINARY ordering.
--
-- The iOS app generates order keys with FractionalIndex, whose midpoint
-- algorithm produces ASCII punctuation characters (e.g. ']' = 0x5D between
-- 'A' = 0x41 and 'z' = 0x7A). SQLite (BINARY collation) sorts these by raw
-- byte value, so locally a sequence appended one-by-one produces keys like
-- "A", "]", "k", "r" that sort in chronological/display order.
--
-- Postgres on Supabase defaults to en_US.UTF-8, which uses ICU/UCA rules:
-- punctuation has different weights than ASCII letters and case is folded.
-- The same keys ("A", "]", "k") sort to a different order under UCA, so
-- shared-page previews showed sections out of order relative to the sharer's
-- editor — and intermittently, depending on whether any generated key
-- happened to land on a character whose UCA weight differs from its byte.
--
-- COLLATE "C" forces byte-wise comparison, matching SQLite.
--
-- Idempotent — safe to re-run.

ALTER TABLE public.sections
  ALTER COLUMN order_key SET DATA TYPE TEXT COLLATE "C";

-- Rebuild the composite index so it uses the new collation. ALTER COLUMN
-- TYPE rebuilds dependent indexes automatically, but we drop/recreate
-- explicitly to keep the migration self-describing.
DROP INDEX IF EXISTS public.idx_sections_order;
CREATE INDEX idx_sections_order ON public.sections (note_id, order_key);
