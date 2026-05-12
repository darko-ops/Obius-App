-- Add subscription tracking columns to user_profiles
-- Used by RevenueCat webhook to persist subscription state server-side, and
-- by the iOS client (StoreManager.syncTierToServer) as a fallback when the
-- webhook is delayed. Other migrations (e.g. 20260430000000_pricing_rework_credits.sql)
-- assume these columns exist.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS rc_app_user_id TEXT,
  ADD COLUMN IF NOT EXISTS subscription_tier TEXT NOT NULL DEFAULT 'free'
    CHECK (subscription_tier IN ('free', 'pro', 'founding')),
  ADD COLUMN IF NOT EXISTS subscription_product_id TEXT,
  ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS subscription_store TEXT,
  ADD COLUMN IF NOT EXISTS is_founding_member BOOLEAN NOT NULL DEFAULT FALSE;

-- Index for webhook lookups by RevenueCat app user ID
CREATE INDEX IF NOT EXISTS idx_user_profiles_rc_app_user_id
  ON public.user_profiles (rc_app_user_id)
  WHERE rc_app_user_id IS NOT NULL;
