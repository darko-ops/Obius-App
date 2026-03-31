-- Subscription conversion funnel events
-- Tracks: paywall_shown → trial_started → converted → churned
-- Plus which feature/limit triggered the paywall

CREATE TABLE IF NOT EXISTS public.subscription_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users,
  event TEXT NOT NULL CHECK (event IN (
    'paywall_shown',
    'paywall_dismissed',
    'trial_started',
    'purchase_completed',
    'purchase_failed',
    'restore_completed',
    'churned',
    'reactivated'
  )),
  trigger_feature TEXT,          -- which GatedFeature triggered it (notes, handles, aiActions, etc.)
  product_id TEXT,               -- RevenueCat product ID
  tier_before TEXT,              -- tier at time of event
  tier_after TEXT,               -- tier after event (for conversions)
  metadata JSONB DEFAULT '{}'::jsonb,  -- extra context (price, offering, experiment variant)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for analytics queries
CREATE INDEX idx_sub_events_user ON public.subscription_events(user_id);
CREATE INDEX idx_sub_events_event ON public.subscription_events(event);
CREATE INDEX idx_sub_events_created ON public.subscription_events(created_at);
CREATE INDEX idx_sub_events_trigger ON public.subscription_events(trigger_feature)
  WHERE trigger_feature IS NOT NULL;

-- RLS: users can read own events, service role inserts
ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own subscription events"
  ON public.subscription_events FOR SELECT
  USING (auth.uid() = user_id);

-- Materialized view for conversion funnel dashboard
-- Run: REFRESH MATERIALIZED VIEW subscription_funnel;
CREATE MATERIALIZED VIEW IF NOT EXISTS public.subscription_funnel AS
SELECT
  trigger_feature,
  COUNT(*) FILTER (WHERE event = 'paywall_shown') AS shown,
  COUNT(*) FILTER (WHERE event = 'trial_started') AS trials,
  COUNT(*) FILTER (WHERE event = 'purchase_completed') AS conversions,
  COUNT(*) FILTER (WHERE event = 'churned') AS churns,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE event = 'trial_started') /
    NULLIF(COUNT(*) FILTER (WHERE event = 'paywall_shown'), 0), 1
  ) AS trial_rate_pct,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE event = 'purchase_completed') /
    NULLIF(COUNT(*) FILTER (WHERE event = 'paywall_shown'), 0), 1
  ) AS conversion_rate_pct
FROM public.subscription_events
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY trigger_feature
ORDER BY shown DESC;
