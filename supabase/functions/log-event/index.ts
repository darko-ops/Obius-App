// OBIUS Subscription Event Logger
// Tracks conversion funnel: paywall_shown → trial_started → converted

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

const VALID_EVENTS = [
  'paywall_shown',
  'paywall_dismissed',
  'trial_started',
  'purchase_completed',
  'purchase_failed',
  'restore_completed',
  'churned',
  'reactivated',
] as const;

interface EventRequest {
  event: string;
  triggerFeature?: string;
  productId?: string;
  tierBefore?: string;
  tierAfter?: string;
  metadata?: Record<string, unknown>;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return corsResponse();

  try {
    let userId: string | null = null;
    try {
      const auth = await verifyAuth(req);
      userId = auth.userId;
    } catch {
      // Anonymous events are allowed
    }

    const supabase = createServiceClient();
    const body: EventRequest = await req.json();

    if (!body.event || !VALID_EVENTS.includes(body.event as typeof VALID_EVENTS[number])) {
      return errorResponse('INVALID_EVENT', `Invalid event type: ${body.event}`);
    }

    const { error } = await supabase
      .from('subscription_events')
      .insert({
        user_id: userId,
        event: body.event,
        trigger_feature: body.triggerFeature ?? null,
        product_id: body.productId ?? null,
        tier_before: body.tierBefore ?? null,
        tier_after: body.tierAfter ?? null,
        metadata: body.metadata ?? {},
      });

    if (error) {
      console.error('[log-event] Insert failed:', error.message);
      // Don't fail the client — analytics should never block UX
      return jsonResponse({ ok: true });
    }

    return jsonResponse({ ok: true });
  } catch (error) {
    console.error('[log-event] Error:', error);
    // Always return success — analytics should never block UX
    return jsonResponse({ ok: true });
  }
});
