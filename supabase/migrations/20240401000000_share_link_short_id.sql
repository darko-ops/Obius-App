-- Add commit_short_id to share_links so the human-readable ID
-- (e.g. OBX-A1B2-C3D4) travels with the shared link.
ALTER TABLE public.share_links
    ADD COLUMN commit_short_id TEXT;

COMMENT ON COLUMN public.share_links.commit_short_id IS 'Human-readable commit short ID (OBX-XXXX-XXXX)';
