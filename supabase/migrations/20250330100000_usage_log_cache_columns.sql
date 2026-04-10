-- Add cache token breakdown columns to usage_log
-- Anthropic API responses include cache_creation_input_tokens and cache_read_input_tokens
-- alongside the base input_tokens count.

ALTER TABLE public.usage_log
  ADD COLUMN IF NOT EXISTS cache_creation_input_tokens INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cache_read_input_tokens INT NOT NULL DEFAULT 0;
