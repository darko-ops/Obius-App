// OBIUS RevenueCat Webhook Handler
// Receives subscription lifecycle events and updates user_profiles accordingly.
//
// Setup in RevenueCat Dashboard → Integrations → Webhooks:
//   URL:  https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook
//   Auth: Bearer <REVENUECAT_WEBHOOK_SECRET>   (set as Supabase secret)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createServiceClient, jsonResponse, errorResponse, corsResponse } from '../_shared/supabase-client.ts';

// ── RevenueCat event types ──────────────────────────────────────────────────

type RCEventType =
  | 'TEST'
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'NON_RENEWING_PURCHASE'
  | 'SUBSCRIPTION_PAUSED'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'PRODUCT_CHANGE'
  | 'TRANSFER'
  | 'SUBSCRIPTION_EXTENDED'
  | 'TEMPORARY_ENTITLEMENT_GRANT'
  | 'REFUND_REVERSED';

interface RCEvent {
  type: RCEventType;
  id: string;
  app_user_id: string;
  original_app_user_id: string;
  aliases: string[];
  product_id?: string;
  entitlement_ids?: string[];
  period_type?: string;
  purchased_at_ms?: number;
  expiration_at_ms?: number;
  store?: string;
  environment?: string;
  cancel_reason?: string;
  expiration_reason?: string;
  new_product_id?: string;
  price?: number;
  currency?: string;
  price_in_purchased_currency?: number;
  country_code?: string;
  event_timestamp_ms: number;
}

interface RCWebhookPayload {
  api_version: string;
  event: RCEvent;
}

// ── Constants ───────────────────────────────────────────────────────────────

const ENTITLEMENT_ID = 'Obius Pro';
const REVENUECAT_API_KEY = Deno.env.get('REVENUECAT_API_KEY')!;
const WEBHOOK_SECRET = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');

if (!WEBHOOK_SECRET) {
  console.error('[RC Webhook] REVENUECAT_WEBHOOK_SECRET is not set — webhook is unprotected!');
}

// Events that grant or extend access
const GRANT_EVENTS: RCEventType[] = [
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'SUBSCRIPTION_EXTENDED',
  'TEMPORARY_ENTITLEMENT_GRANT',
  'REFUND_REVERSED',
];

// Events that revoke access
const REVOKE_EVENTS: RCEventType[] = [
  'CANCELLATION',
  'EXPIRATION',
];

// ── Handler ─────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  if (req.method !== 'POST') {
    return errorResponse('method_not_allowed', 'POST only', 405);
  }

  // Verify webhook authenticity
  const auth = req.headers.get('Authorization');
  if (!WEBHOOK_SECRET || auth !== `Bearer ${WEBHOOK_SECRET}`) {
    console.error('[RC Webhook] Invalid or missing authorization');
    return errorResponse('unauthorized', 'Invalid webhook secret', 401);
  }

  let payload: RCWebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }

  const event = payload.event;
  console.log(`[RC Webhook] ${event.type} | user=${event.app_user_id} | product=${event.product_id ?? 'n/a'} | env=${event.environment ?? 'n/a'}`);

  // Acknowledge TEST events immediately
  if (event.type === 'TEST') {
    return jsonResponse({ ok: true, message: 'Test event received' });
  }

  // Only process events that affect the "Obius Pro" entitlement
  const affectsEntitlement =
    !event.entitlement_ids || event.entitlement_ids.length === 0 || event.entitlement_ids.includes(ENTITLEMENT_ID);

  if (!affectsEntitlement) {
    return jsonResponse({ ok: true, message: 'Ignored — unrelated entitlement' });
  }

  const supabase = createServiceClient();

  // Resolve Supabase user ID — app_user_id is the lowercased Supabase UUID
  // (set via Purchases.shared.logIn() on the client)
  const userId = event.app_user_id;

  // Check user exists
  const { data: profile } = await supabase
    .from('user_profiles')
    .select('id')
    .eq('id', userId)
    .maybeSingle();

  if (!profile) {
    // Try aliases (original_app_user_id, aliases array)
    const candidates = [event.original_app_user_id, ...event.aliases].filter(Boolean);
    let resolvedId: string | null = null;

    for (const candidate of candidates) {
      // Check by id first
      const { data: byId } = await supabase
        .from('user_profiles')
        .select('id')
        .eq('id', candidate)
        .maybeSingle();
      if (byId) { resolvedId = byId.id; break; }

      // Then check by rc_app_user_id
      const { data: byRc } = await supabase
        .from('user_profiles')
        .select('id')
        .eq('rc_app_user_id', candidate)
        .maybeSingle();
      if (byRc) { resolvedId = byRc.id; break; }
    }

    if (!resolvedId) {
      console.warn(`[RC Webhook] No user found for ${userId} or aliases`);
      // Return 200 so RevenueCat doesn't retry
      return jsonResponse({ ok: true, message: 'User not found — skipped' });
    }

    return await processEvent(supabase, resolvedId, event);
  }

  return await processEvent(supabase, userId, event);
});

// ── Process event ───────────────────────────────────────────────────────────

async function processEvent(supabase: any, userId: string, event: RCEvent): Promise<Response> {
  if (GRANT_EVENTS.includes(event.type)) {
    const tier = determineTier(event.product_id);
    const expiresAt = event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null;

    const { error } = await supabase
      .from('user_profiles')
      .update({
        rc_app_user_id: event.app_user_id,
        subscription_tier: tier,
        subscription_product_id: event.product_id ?? null,
        subscription_expires_at: expiresAt,
        subscription_store: event.store ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', userId);

    if (error) {
      console.error(`[RC Webhook] Failed to grant: ${error.message}`);
      return errorResponse('db_error', error.message, 500);
    }

    // Log conversion event
    const analyticsEvent = event.type === 'INITIAL_PURCHASE' ? 'purchase_completed'
      : event.type === 'UNCANCELLATION' ? 'reactivated'
      : null;
    if (analyticsEvent) {
      await supabase.from('subscription_events').insert({
        user_id: userId,
        event: analyticsEvent,
        product_id: event.product_id,
        tier_before: 'free',
        tier_after: tier,
        metadata: { store: event.store, environment: event.environment },
      }).then(() => {}, () => {}); // fire-and-forget
    }

    console.log(`[RC Webhook] Granted ${tier} to ${userId} (expires ${expiresAt ?? 'never'})`);
    return jsonResponse({ ok: true, tier });
  }

  if (REVOKE_EVENTS.includes(event.type)) {
    // Check if user is a founding member — they keep access
    const { data: profile } = await supabase
      .from('user_profiles')
      .select('is_founding_member')
      .eq('id', userId)
      .single();

    const newTier = profile?.is_founding_member ? 'founding' : 'free';

    const { error } = await supabase
      .from('user_profiles')
      .update({
        subscription_tier: newTier,
        subscription_product_id: null,
        subscription_expires_at: null,
        subscription_store: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', userId);

    if (error) {
      console.error(`[RC Webhook] Failed to revoke: ${error.message}`);
      return errorResponse('db_error', error.message, 500);
    }

    // Log churn event
    await supabase.from('subscription_events').insert({
      user_id: userId,
      event: 'churned',
      product_id: event.product_id,
      tier_before: 'pro',
      tier_after: newTier,
      metadata: {
        reason: event.cancel_reason ?? event.expiration_reason ?? event.type,
        store: event.store,
      },
    }).then(() => {}, () => {}); // fire-and-forget

    console.log(`[RC Webhook] Revoked → ${newTier} for ${userId} (${event.type})`);
    return jsonResponse({ ok: true, tier: newTier });
  }

  if (event.type === 'BILLING_ISSUE') {
    console.warn(`[RC Webhook] Billing issue for ${userId} — product ${event.product_id}`);
    // Keep access during grace period; EXPIRATION will fire if not resolved
    return jsonResponse({ ok: true, message: 'Billing issue noted' });
  }

  if (event.type === 'PRODUCT_CHANGE') {
    const newTier = determineTier(event.new_product_id);

    const { error } = await supabase
      .from('user_profiles')
      .update({
        subscription_tier: newTier,
        subscription_product_id: event.new_product_id ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', userId);

    if (error) {
      console.error(`[RC Webhook] Failed to update product: ${error.message}`);
      return errorResponse('db_error', error.message, 500);
    }

    console.log(`[RC Webhook] Product change → ${newTier} for ${userId}`);
    return jsonResponse({ ok: true, tier: newTier });
  }

  // SUBSCRIPTION_PAUSED, TRANSFER, etc. — acknowledge without action
  console.log(`[RC Webhook] No action for ${event.type}`);
  return jsonResponse({ ok: true, message: `${event.type} acknowledged` });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function determineTier(productId: string | undefined): string {
  if (!productId) return 'pro';

  // Lifetime purchases get pro
  if (productId.includes('lifetime')) return 'pro';
  // Founding member products
  if (productId.includes('founding')) return 'founding';
  // Everything else is pro
  return 'pro';
}
