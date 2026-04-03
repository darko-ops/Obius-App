-- Add provider column to usage_log for multi-AI orchestration tracking.
-- Tracks which AI provider (anthropic, gemini, openai) served each request.

ALTER TABLE usage_log
  ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'anthropic';

-- Index for provider-level analytics
CREATE INDEX IF NOT EXISTS idx_usage_log_provider ON usage_log (provider);

-- Backfill: all existing rows were served by Anthropic
-- (no UPDATE needed since the DEFAULT handles it)
