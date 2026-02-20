-- Store creator name/email directly on the share link so viewers
-- always see who created it without needing to look up auth.users.
ALTER TABLE public.share_links
    ADD COLUMN creator_name TEXT;

COMMENT ON COLUMN public.share_links.creator_name IS 'Display name or email of the share creator';
