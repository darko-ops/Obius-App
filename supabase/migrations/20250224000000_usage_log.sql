create table public.usage_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  action text not null,
  input_tokens int not null,
  output_tokens int not null,
  model text not null,
  created_at timestamptz default now()
);

-- Index for per-user queries and cost dashboards
create index idx_usage_log_user_id on public.usage_log(user_id);
create index idx_usage_log_created_at on public.usage_log(created_at);

-- RLS: users can read their own usage, only service role can insert
alter table public.usage_log enable row level security;

create policy "Users can read own usage"
  on public.usage_log for select
  using (auth.uid() = user_id);
