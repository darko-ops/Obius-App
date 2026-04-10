// OBIUS Usage Analytics Edge Function
// Ingest and query API usage data (matches Anthropic billing export format).
//
// POST /usage-analytics  { action: "ingest", rows: [...] }  — bulk-insert daily usage rows
// POST /usage-analytics  { action: "query",  startDate, endDate }  — get usage for date range
// POST /usage-analytics  { action: "cost_by_model", startDate, endDate }  — get cost breakdown

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

// ---------- Types ----------

interface UsageRow {
  usage_date_utc: string;
  model_version: string;
  api_key?: string;
  workspace?: string;
  usage_type?: string;
  context_window?: string;
  usage_input_tokens_no_cache: number;
  usage_input_tokens_cache_write_5m?: number;
  usage_input_tokens_cache_write_1h?: number;
  usage_input_tokens_cache_read?: number;
  usage_output_tokens: number;
  web_search_count?: number;
  inference_geo?: string;
}

interface IngestRequest {
  action: 'ingest';
  rows: UsageRow[];
}

interface QueryRequest {
  action: 'query' | 'cost_by_model';
  startDate?: string;   // YYYY-MM-DD
  endDate?: string;     // YYYY-MM-DD
}

type ActionRequest = IngestRequest | QueryRequest;

// ---------- Handlers ----------

async function handleIngest(rows: UsageRow[], userId: string) {
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse('INVALID_REQUEST', 'rows array is required and must not be empty');
  }

  if (rows.length > 1000) {
    return errorResponse('INVALID_REQUEST', 'Maximum 1000 rows per request');
  }

  const supabase = createServiceClient();

  const records = rows.map((r) => ({
    user_id: userId,
    usage_date: r.usage_date_utc,
    model_version: r.model_version,
    api_key_name: r.api_key ?? 'default',
    workspace: r.workspace ?? 'Default',
    usage_type: r.usage_type ?? 'standard',
    context_window: r.context_window ?? null,
    input_tokens_no_cache: r.usage_input_tokens_no_cache ?? 0,
    input_tokens_cache_write_5m: r.usage_input_tokens_cache_write_5m ?? 0,
    input_tokens_cache_write_1h: r.usage_input_tokens_cache_write_1h ?? 0,
    input_tokens_cache_read: r.usage_input_tokens_cache_read ?? 0,
    output_tokens: r.usage_output_tokens ?? 0,
    web_search_count: r.web_search_count ?? 0,
    inference_geo: r.inference_geo ?? 'not_available',
  }));

  // Upsert: if a row for the same user/date/model/workspace/type/window exists, update it
  const { data, error } = await supabase
    .from('api_usage_analytics')
    .upsert(records, {
      onConflict: 'user_id,usage_date,model_version,workspace,usage_type,context_window',
    })
    .select('id');

  if (error) {
    console.error('[usage-analytics] Ingest error:', error.message);
    return errorResponse('INSERT_FAILED', error.message, 500);
  }

  return jsonResponse({ ok: true, inserted: data?.length ?? 0 });
}

async function handleQuery(userId: string, startDate?: string, endDate?: string) {
  const supabase = createServiceClient();

  const start = startDate ?? new Date(Date.now() - 30 * 86400000).toISOString().split('T')[0];
  const end = endDate ?? new Date().toISOString().split('T')[0];

  const { data, error } = await supabase
    .from('api_usage_analytics')
    .select('*')
    .eq('user_id', userId)
    .gte('usage_date', start)
    .lte('usage_date', end)
    .order('usage_date', { ascending: false })
    .order('model_version');

  if (error) {
    console.error('[usage-analytics] Query error:', error.message);
    return errorResponse('QUERY_FAILED', error.message, 500);
  }

  // Compute totals
  const totals = (data ?? []).reduce(
    (acc, row) => {
      acc.input_tokens += (row.input_tokens_no_cache ?? 0) +
        (row.input_tokens_cache_write_5m ?? 0) +
        (row.input_tokens_cache_write_1h ?? 0) +
        (row.input_tokens_cache_read ?? 0);
      acc.output_tokens += row.output_tokens ?? 0;
      acc.estimated_cost += parseFloat(row.estimated_cost_usd ?? '0');
      acc.web_searches += row.web_search_count ?? 0;
      return acc;
    },
    { input_tokens: 0, output_tokens: 0, estimated_cost: 0, web_searches: 0 },
  );

  totals.estimated_cost = Math.round(totals.estimated_cost * 1000000) / 1000000;

  return jsonResponse({
    rows: data,
    totals,
    period: { start, end },
  });
}

async function handleCostByModel(userId: string, startDate?: string, endDate?: string) {
  const supabase = createServiceClient();

  const start = startDate ?? new Date(Date.now() - 30 * 86400000).toISOString().split('T')[0];
  const end = endDate ?? new Date().toISOString().split('T')[0];

  const { data, error } = await supabase
    .from('api_usage_analytics')
    .select('model_version, input_tokens_no_cache, input_tokens_cache_write_5m, input_tokens_cache_write_1h, input_tokens_cache_read, output_tokens, estimated_cost_usd, usage_date')
    .eq('user_id', userId)
    .gte('usage_date', start)
    .lte('usage_date', end);

  if (error) {
    console.error('[usage-analytics] Cost query error:', error.message);
    return errorResponse('QUERY_FAILED', error.message, 500);
  }

  // Aggregate by model
  const byModel: Record<string, {
    model_version: string;
    total_input_tokens: number;
    total_output_tokens: number;
    total_cost: number;
    days_active: Set<string>;
  }> = {};

  for (const row of data ?? []) {
    const key = row.model_version;
    if (!byModel[key]) {
      byModel[key] = {
        model_version: key,
        total_input_tokens: 0,
        total_output_tokens: 0,
        total_cost: 0,
        days_active: new Set(),
      };
    }
    const m = byModel[key];
    m.total_input_tokens += (row.input_tokens_no_cache ?? 0) +
      (row.input_tokens_cache_write_5m ?? 0) +
      (row.input_tokens_cache_write_1h ?? 0) +
      (row.input_tokens_cache_read ?? 0);
    m.total_output_tokens += row.output_tokens ?? 0;
    m.total_cost += parseFloat(row.estimated_cost_usd ?? '0');
    m.days_active.add(row.usage_date);
  }

  const models = Object.values(byModel)
    .map((m) => ({
      model_version: m.model_version,
      total_input_tokens: m.total_input_tokens,
      total_output_tokens: m.total_output_tokens,
      total_cost: Math.round(m.total_cost * 1000000) / 1000000,
      days_active: m.days_active.size,
    }))
    .sort((a, b) => b.total_cost - a.total_cost);

  return jsonResponse({
    models,
    period: { start, end },
  });
}

// ---------- Router ----------

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return corsResponse();

  try {
    const { userId } = await verifyAuth(req);
    const body: ActionRequest = await req.json();

    switch (body.action) {
      case 'ingest':
        return await handleIngest((body as IngestRequest).rows, userId);
      case 'query':
        return await handleQuery(userId, (body as QueryRequest).startDate, (body as QueryRequest).endDate);
      case 'cost_by_model':
        return await handleCostByModel(userId, (body as QueryRequest).startDate, (body as QueryRequest).endDate);
      default:
        return errorResponse('UNKNOWN_ACTION', `Unknown action: ${(body as { action: string }).action}`);
    }
  } catch (error) {
    console.error('[usage-analytics] Error:', error);
    if (error.name === 'AuthError') {
      return errorResponse('UNAUTHORIZED', 'Valid authentication required for usage analytics', 401);
    }
    return errorResponse('INTERNAL_ERROR', error.message || 'An unexpected error occurred', 500);
  }
});
