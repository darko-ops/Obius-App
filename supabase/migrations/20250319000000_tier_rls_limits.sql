-- Tier-aware RLS: enforce entity creation limits at the database level.
-- Free-tier users are capped at 25 notes. Pro/founding are unlimited.
-- This is a defense-in-depth layer — Edge Functions also check limits.

-- Helper function: returns the subscription tier for the current user
CREATE OR REPLACE FUNCTION public.get_user_tier()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(subscription_tier, 'free')
  FROM public.user_profiles
  WHERE id = auth.uid()
$$;

-- Helper function: returns note count for the current user
CREATE OR REPLACE FUNCTION public.user_note_count()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COUNT(*)
  FROM public.notes
  WHERE user_id = auth.uid()
    AND deleted_at IS NULL
$$;

-- Replace the existing notes INSERT policy with a tier-aware version
DROP POLICY IF EXISTS "Users can create own notes" ON public.notes;

CREATE POLICY "Users can create own notes"
  ON public.notes FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND (
      public.get_user_tier() IN ('pro', 'founding')
      OR public.user_note_count() < 25
    )
  );

-- Replace the existing share_links INSERT policy with a tier-aware version
-- Only pro/founding users can create share links
DROP POLICY IF EXISTS "Users can manage own share links" ON public.share_links;

CREATE POLICY "Users can create share links"
  ON public.share_links FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND public.get_user_tier() IN ('pro', 'founding')
  );

-- Keep existing select/update/delete policies for share_links
CREATE POLICY "Users can manage own share links"
  ON public.share_links FOR ALL
  USING (auth.uid() = user_id);

-- Re-create the public read policy for share_links
DROP POLICY IF EXISTS "Anyone can view active share links" ON public.share_links;

CREATE POLICY "Anyone can view active share links"
  ON public.share_links FOR SELECT
  USING (is_active = true);
