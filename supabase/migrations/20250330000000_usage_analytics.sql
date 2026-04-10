-- Usage Analytics Schema
-- Stores granular API usage data matching the Anthropic billing export format.
-- Supports: token breakdown (cache write/read), cost calculation, daily aggregation.

-- ============================================================================
-- 1. Core analytics table (daily aggregated usage per model/workspace)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.api_usage_analytics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users NOT NULL,

  -- Dimensions (matches Anthropic billing export)
  usage_date DATE NOT NULL,
  model_version TEXT NOT NULL,
  api_key_name TEXT NOT NULL DEFAULT 'default',
  workspace TEXT NOT NULL DEFAULT 'Default',
  usage_type TEXT NOT NULL DEFAULT 'standard',
  context_window TEXT,                          -- e.g. '≤ 200k', '≤ 1m'

  -- Token breakdown
  input_tokens_no_cache BIGINT NOT NULL DEFAULT 0,
  input_tokens_cache_write_5m BIGINT NOT NULL DEFAULT 0,
  input_tokens_cache_write_1h BIGINT NOT NULL DEFAULT 0,
  input_tokens_cache_read BIGINT NOT NULL DEFAULT 0,
  output_tokens BIGINT NOT NULL DEFAULT 0,

  -- Extended metrics
  web_search_count INT NOT NULL DEFAULT 0,
  inference_geo TEXT DEFAULT 'not_available',

  -- Cost tracking (auto-calculated by trigger)
  estimated_cost_usd NUMERIC(12, 6) DEFAULT 0,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One row per user/date/model/workspace/usage_type/context_window
  CONSTRAINT uq_usage_analytics_key
    UNIQUE (user_id, usage_date, model_version, workspace, usage_type, context_window)
);

-- ============================================================================
-- 2. Indexes
-- ============================================================================

CREATE INDEX idx_usage_analytics_user_id ON public.api_usage_analytics(user_id);
CREATE INDEX idx_usage_analytics_date ON public.api_usage_analytics(usage_date);
CREATE INDEX idx_usage_analytics_user_date ON public.api_usage_analytics(user_id, usage_date DESC);
CREATE INDEX idx_usage_analytics_model ON public.api_usage_analytics(model_version);

-- ============================================================================
-- 3. Row Level Security
-- ============================================================================

ALTER TABLE public.api_usage_analytics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own usage analytics"
  ON public.api_usage_analytics FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role can insert usage analytics"
  ON public.api_usage_analytics FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Service role can update usage analytics"
  ON public.api_usage_analytics FOR UPDATE
  USING (true);

-- ============================================================================
-- 4. Cost calculation function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calculate_usage_cost(
  p_model TEXT,
  p_input_tokens_no_cache BIGINT,
  p_input_tokens_cache_write_5m BIGINT DEFAULT 0,
  p_input_tokens_cache_write_1h BIGINT DEFAULT 0,
  p_input_tokens_cache_read BIGINT DEFAULT 0,
  p_output_tokens BIGINT DEFAULT 0
) RETURNS NUMERIC AS $$
DECLARE
  input_rate NUMERIC;
  cache_write_rate NUMERIC;
  cache_read_rate NUMERIC;
  output_rate NUMERIC;
BEGIN
  -- Rates per million tokens (USD) — Anthropic pricing as of 2025
  IF p_model ILIKE '%haiku%' THEN
    input_rate := 0.80;
    cache_write_rate := 1.00;
    cache_read_rate := 0.08;
    output_rate := 4.00;
  ELSIF p_model ILIKE '%sonnet%' THEN
    input_rate := 3.00;
    cache_write_rate := 3.75;
    cache_read_rate := 0.30;
    output_rate := 15.00;
  ELSIF p_model ILIKE '%opus%' THEN
    input_rate := 15.00;
    cache_write_rate := 18.75;
    cache_read_rate := 1.50;
    output_rate := 75.00;
  ELSE
    -- Default to Sonnet pricing
    input_rate := 3.00;
    cache_write_rate := 3.75;
    cache_read_rate := 0.30;
    output_rate := 15.00;
  END IF;

  RETURN ROUND((
    (p_input_tokens_no_cache * input_rate) +
    ((p_input_tokens_cache_write_5m + p_input_tokens_cache_write_1h) * cache_write_rate) +
    (p_input_tokens_cache_read * cache_read_rate) +
    (p_output_tokens * output_rate)
  ) / 1000000.0, 6);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- 5. Auto-calculate cost on insert/update
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_auto_calculate_usage_cost()
RETURNS TRIGGER AS $$
BEGIN
  NEW.estimated_cost_usd := public.calculate_usage_cost(
    NEW.model_version,
    NEW.input_tokens_no_cache,
    NEW.input_tokens_cache_write_5m,
    NEW.input_tokens_cache_write_1h,
    NEW.input_tokens_cache_read,
    NEW.output_tokens
  );
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_usage_analytics_cost
  BEFORE INSERT OR UPDATE ON public.api_usage_analytics
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_calculate_usage_cost();

-- ============================================================================
-- 6. Materialized view: daily usage summary from existing usage_log
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_usage_summary AS
SELECT
  user_id,
  DATE(created_at AT TIME ZONE 'UTC') AS usage_date,
  model,
  action,
  COUNT(*) AS request_count,
  SUM(input_tokens) AS total_input_tokens,
  SUM(output_tokens) AS total_output_tokens,
  SUM(input_tokens + output_tokens) AS total_tokens,
  CASE
    WHEN model ILIKE '%haiku%' THEN
      ROUND((SUM(input_tokens) * 0.80 + SUM(output_tokens) * 4.00) / 1000000.0, 6)
    WHEN model ILIKE '%sonnet%' THEN
      ROUND((SUM(input_tokens) * 3.00 + SUM(output_tokens) * 15.00) / 1000000.0, 6)
    WHEN model ILIKE '%opus%' THEN
      ROUND((SUM(input_tokens) * 15.00 + SUM(output_tokens) * 75.00) / 1000000.0, 6)
    ELSE
      ROUND((SUM(input_tokens) * 3.00 + SUM(output_tokens) * 15.00) / 1000000.0, 6)
  END AS estimated_cost_usd
FROM public.usage_log
GROUP BY user_id, DATE(created_at AT TIME ZONE 'UTC'), model, action;

CREATE UNIQUE INDEX idx_daily_usage_summary_key
  ON public.daily_usage_summary(user_id, usage_date, model, action);

-- ============================================================================
-- 7. Helper function: get usage summary for a date range
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_usage_analytics(
  p_user_id UUID,
  p_start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
  p_end_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  usage_date DATE,
  model_version TEXT,
  total_input_tokens BIGINT,
  total_cached_tokens BIGINT,
  total_output_tokens BIGINT,
  total_tokens BIGINT,
  estimated_cost NUMERIC,
  web_searches INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.usage_date,
    a.model_version,
    a.input_tokens_no_cache AS total_input_tokens,
    (a.input_tokens_cache_write_5m + a.input_tokens_cache_write_1h +
     a.input_tokens_cache_read) AS total_cached_tokens,
    a.output_tokens AS total_output_tokens,
    (a.input_tokens_no_cache + a.input_tokens_cache_write_5m +
     a.input_tokens_cache_write_1h + a.input_tokens_cache_read +
     a.output_tokens) AS total_tokens,
    a.estimated_cost_usd AS estimated_cost,
    a.web_search_count AS web_searches
  FROM public.api_usage_analytics a
  WHERE a.user_id = p_user_id
    AND a.usage_date BETWEEN p_start_date AND p_end_date
  ORDER BY a.usage_date DESC, a.model_version;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================================
-- 8. Helper function: get cost totals grouped by model
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_usage_cost_by_model(
  p_user_id UUID,
  p_start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
  p_end_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  model_version TEXT,
  total_input_tokens BIGINT,
  total_output_tokens BIGINT,
  total_cost NUMERIC,
  days_active BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.model_version,
    SUM(a.input_tokens_no_cache + a.input_tokens_cache_write_5m +
        a.input_tokens_cache_write_1h + a.input_tokens_cache_read)::BIGINT AS total_input_tokens,
    SUM(a.output_tokens)::BIGINT AS total_output_tokens,
    SUM(a.estimated_cost_usd) AS total_cost,
    COUNT(DISTINCT a.usage_date) AS days_active
  FROM public.api_usage_analytics a
  WHERE a.user_id = p_user_id
    AND a.usage_date BETWEEN p_start_date AND p_end_date
  GROUP BY a.model_version
  ORDER BY total_cost DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
