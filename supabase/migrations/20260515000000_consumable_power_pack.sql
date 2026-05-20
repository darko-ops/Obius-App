-- Power Pack: subscription rider → consumable IAP
--
-- The Power Pack (`credits_pack_10`) is now a *consumable* one-time
-- purchase, not an auto-renewing add-on entitlement. Each purchase grants
-- +1,000 Credits to the user's current monthly cycle. Users may buy any
-- number of packs per month; the bonus resets on the 1st of the next UTC
-- month alongside the base tier's allotment.
--
-- Schema changes:
--   + bonus_credits_this_month INTEGER  — current cycle's top-up balance
--   + bonus_credits_month_key   TEXT     — 'YYYY-MM' the balance applies to;
--                                          mismatch with current month ⇒ 0
--   − has_power_addon BOOLEAN            — superseded by the integer above
--
-- Deploy order: ship the updated `revenuecat-webhook` Edge Function first
-- (it no longer writes `has_power_addon`), THEN run this migration, then
-- ship the iOS build that reads the new columns. Doing it in this order
-- avoids a window where the webhook tries to write a dropped column.
--
-- Idempotent — safe to re-run.

-- ── 1. Add new columns ─────────────────────────────────────────────────────

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS bonus_credits_this_month INTEGER NOT NULL DEFAULT 0
    CHECK (bonus_credits_this_month >= 0);

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS bonus_credits_month_key TEXT
    CHECK (bonus_credits_month_key IS NULL OR bonus_credits_month_key ~ '^[0-9]{4}-[0-9]{2}$');

COMMENT ON COLUMN public.user_profiles.bonus_credits_this_month IS
  'Power Pack top-ups granted to the current monthly cycle. Each consumable purchase of credits_pack_10 adds 1000. Resets to 0 when bonus_credits_month_key falls out of date.';

COMMENT ON COLUMN public.user_profiles.bonus_credits_month_key IS
  'YYYY-MM (UTC) the bonus balance applies to. If it does not match the current month, bonus_credits_this_month should be treated as 0 (the cycle has rolled over). Server-side helpers and the iOS client both apply this rule.';

-- ── 2. Drop the legacy Bool column ─────────────────────────────────────────
--
-- Both the Edge Function and the iOS client stopped reading/writing
-- `has_power_addon` in this release. Dropping it now prevents stale data
-- from being interpreted by any future code path.

ALTER TABLE public.user_profiles
  DROP COLUMN IF EXISTS has_power_addon;

-- ── 3. Updated credit cap helper ──────────────────────────────────────────
--
-- `credits_used_this_month()` is unchanged — it returns *used* credits.
-- This new helper returns the *cap*: base tier allotment plus the current
-- cycle's Power Pack bonus. Used by Edge Functions to decide whether to
-- gate AI work.

CREATE OR REPLACE FUNCTION public.effective_credit_cap(p_user_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $fn$
DECLARE
  v_tier   TEXT;
  v_period TEXT;
  v_bonus  INTEGER;
  v_key    TEXT;
  v_now    TEXT := to_char(timezone('UTC', now()), 'YYYY-MM');
  v_base   INTEGER;
  v_cycle_bonus INTEGER;
BEGIN
  SELECT subscription_tier, subscription_period,
         COALESCE(bonus_credits_this_month, 0), bonus_credits_month_key
    INTO v_tier, v_period, v_bonus, v_key
    FROM public.user_profiles
    WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN 5; -- treat unknown as free
  END IF;

  v_base := CASE v_tier
    WHEN 'pro'      THEN CASE v_period WHEN 'annual' THEN 250 ELSE 200 END
    WHEN 'founding' THEN 200
    ELSE 5
  END;

  v_cycle_bonus := CASE WHEN v_key = v_now THEN v_bonus ELSE 0 END;
  RETURN (v_base + v_cycle_bonus)::BIGINT;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.effective_credit_cap(UUID) TO authenticated, service_role;

-- ── 4. RPC: increment Power Pack bonus ────────────────────────────────────
--
-- Called by the RevenueCat webhook on NON_RENEWING_PURCHASE for the
-- credits_pack_10 product. Atomically resets the cycle if the stored
-- month-key is stale, then adds the requested amount. Returns the new
-- balance so the webhook can log it.

CREATE OR REPLACE FUNCTION public.grant_power_pack_credits(
  p_user_id UUID,
  p_amount  INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_now      TEXT := to_char(timezone('UTC', now()), 'YYYY-MM');
  v_key      TEXT;
  v_bonus    INTEGER;
  v_starting INTEGER;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'grant_power_pack_credits requires positive amount, got %', p_amount;
  END IF;

  SELECT bonus_credits_month_key, COALESCE(bonus_credits_this_month, 0)
    INTO v_key, v_bonus
    FROM public.user_profiles
    WHERE id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_profiles row not found for %', p_user_id;
  END IF;

  v_starting := CASE WHEN v_key = v_now THEN v_bonus ELSE 0 END;

  UPDATE public.user_profiles
     SET bonus_credits_this_month = v_starting + p_amount,
         bonus_credits_month_key  = v_now,
         updated_at               = now()
   WHERE id = p_user_id;

  RETURN v_starting + p_amount;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.grant_power_pack_credits(UUID, INTEGER) TO service_role;
