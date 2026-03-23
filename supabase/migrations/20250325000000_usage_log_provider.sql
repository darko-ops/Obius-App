-- Add provider column to usage_log for easier cost analysis across AI providers.
-- Values: 'claude', 'gemini', 'openai'
alter table public.usage_log add column provider text not null default 'claude';

-- Index for per-provider cost queries
create index idx_usage_log_provider on public.usage_log(provider);

-- Backfill existing rows based on model name
update public.usage_log set provider = 'gemini' where model like 'gemini%';
update public.usage_log set provider = 'openai' where model like 'text-embedding%';
