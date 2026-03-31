-- Add body and interstitial content columns to notes table
ALTER TABLE public.notes ADD COLUMN IF NOT EXISTS body TEXT NOT NULL DEFAULT '';
ALTER TABLE public.notes ADD COLUMN IF NOT EXISTS body_rich_text TEXT;
ALTER TABLE public.notes ADD COLUMN IF NOT EXISTS interstitial_content TEXT NOT NULL DEFAULT '{}';
ALTER TABLE public.notes ADD COLUMN IF NOT EXISTS interstitial_rich_content TEXT NOT NULL DEFAULT '{}';
