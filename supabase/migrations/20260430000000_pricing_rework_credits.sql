-- Unit Economics Rework: tokens → Credits, monthly window, Power Add-on, billing period
--
-- Adds two columns to user_profiles:
--   subscription_period TEXT  ('monthly' | 'annual' | NULL)  — distinguishes Pro Monthly from Pro Annual
--   has_power_addon     BOOL  (default FALSE)                — independent +1,000 Credits/mo entitlement
--
-- Idempotent + bulletproof:
--   - Safe to re-run.
--   - Self-bootstraps `public.usage_log` if a previous environment never had
--     `20250224000000_usage_log.sql` applied via the Dashboard SQL Editor.
--   - Every usage_log statement is guarded with an existence check so partial
--     pastes / out-of-order execution can't fail with relation-does-not-exist.
--   - The credits_used_this_month() function uses LANGUAGE plpgsql for late
--     binding so it can be defined before the table physically exists.

-- ── 1. user_profiles columns ────────────────────────────────────────────────

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS subscription_period TEXT
    CHECK (subscription_period IS NULL OR subscription_period IN ('monthly', 'annual'));

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS has_power_addon BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.user_profiles.subscription_period IS
  'For Pro tier only: ''monthly'' or ''annual''. NULL for free, founding, or unknown. Drives credit cap (200 vs 250).';

COMMENT ON COLUMN public.user_profiles.has_power_addon IS
  'Power Add-on entitlement (separate $9.99/mo product). Grants +1,000 Credits/month on top of the base tier.';

-- ── 2. usage_log bootstrap (matches 20250224000000_usage_log.sql) ──────────

CREATE TABLE IF NOT EXISTS public.usage_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users NOT NULL,
  action TEXT NOT NULL,
  input_tokens INT NOT NULL,
  output_tokens INT NOT NULL,
  model TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── 3. usage_log indexes + RLS (guarded) ────────────────────────────────────

DO $usage_log_setup$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'usage_log'
  ) THEN
    -- Original indexes from the bootstrap migration
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_usage_log_user_id ON public.usage_log(user_id)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_usage_log_created_at ON public.usage_log(created_at)';

    -- Hot-path composite index for the monthly aggregation
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_usage_log_user_created ON public.usage_log (user_id, created_at DESC)';

    -- Enable RLS (idempotent)
    EXECUTE 'ALTER TABLE public.usage_log ENABLE ROW LEVEL SECURITY';

    -- "Users can read own usage" — guarded so re-run doesn't error on duplicate policy
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'usage_log' AND policyname = 'Users can read own usage'
    ) THEN
      EXECUTE 'CREATE POLICY "Users can read own usage" ON public.usage_log FOR SELECT USING (auth.uid() = user_id)';
    END IF;
  END IF;
END
$usage_log_setup$;

-- ── 4. credits_used_this_month(p_user_id) helper ───────────────────────────
--
-- 1 Credit = 1,000 tokens (input + output combined). Resets on the 1st of each
-- calendar month, UTC. LANGUAGE plpgsql so the function definition does NOT
-- bind to public.usage_log at definition time — it binds at call time, which
-- means this CREATE FUNCTION succeeds even if (somehow) the table is missing.

CREATE OR REPLACE FUNCTION public.credits_used_this_month(p_user_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $fn$
DECLARE
  total_credits BIGINT;
BEGIN
  SELECT COALESCE(SUM(input_tokens + output_tokens), 0) / 1000
    INTO total_credits
    FROM public.usage_log
    WHERE user_id = p_user_id
      AND created_at >= date_trunc('month', timezone('UTC', now()));
  RETURN total_credits;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.credits_used_this_month(UUID) TO authenticated, service_role;
