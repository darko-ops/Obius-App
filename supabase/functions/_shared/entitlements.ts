// Server-side entitlement checks
// Uses the subscription_tier column set by the RevenueCat webhook

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { errorResponse } from './supabase-client.ts';

export type SubscriptionTier = 'free' | 'pro' | 'founding';

interface UserTierInfo {
  tier: SubscriptionTier;
  isFoundingMember: boolean;
  expiresAt: string | null;
}

// Per-tier daily AI action limits (must match iOS TierLimits)
const AI_ACTION_LIMITS: Record<SubscriptionTier, number> = {
  free: 10,
  pro: 100,
  founding: 100,
};

// Per-tier entity limits (null = unlimited, must match iOS TierLimits)
interface TierLimits {
  maxNotes: number | null;
  maxSectionsPerNote: number | null;
  cloudSync: boolean;
  shareLinks: boolean;
}

const TIER_LIMITS: Record<SubscriptionTier, TierLimits> = {
  free: {
    maxNotes: 50,
    maxSectionsPerNote: null,
    cloudSync: false,
    shareLinks: false,
  },
  pro: {
    maxNotes: null,
    maxSectionsPerNote: null,
    cloudSync: true,
    shareLinks: true,
  },
  founding: {
    maxNotes: null,
    maxSectionsPerNote: null,
    cloudSync: true,
    shareLinks: true,
  },
};

export function getLimits(tier: SubscriptionTier): TierLimits {
  return TIER_LIMITS[tier];
}

/**
 * Get the subscription tier for a user from the database.
 */
export async function getUserTier(
  supabase: SupabaseClient,
  userId: string,
): Promise<UserTierInfo> {
  const { data, error } = await supabase
    .from('user_profiles')
    .select('subscription_tier, is_founding_member, subscription_expires_at')
    .eq('id', userId)
    .single();

  if (error || !data) {
    console.warn(`[Entitlements] Could not fetch tier for ${userId}: ${error?.message}`);
    return { tier: 'free', isFoundingMember: false, expiresAt: null };
  }

  let tier = data.subscription_tier as SubscriptionTier;

  // Check if subscription has expired (webhook may have been delayed)
  if (tier !== 'free' && data.subscription_expires_at) {
    const expiresAt = new Date(data.subscription_expires_at);
    if (expiresAt < new Date()) {
      // Expired — founding members keep access, others revert
      tier = data.is_founding_member ? 'founding' : 'free';
    }
  }

  return {
    tier,
    isFoundingMember: data.is_founding_member ?? false,
    expiresAt: data.subscription_expires_at,
  };
}

/**
 * Check if a user has Pro-level access (pro or founding).
 */
export async function hasProAccess(
  supabase: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { tier } = await getUserTier(supabase, userId);
  return tier === 'pro' || tier === 'founding';
}

/**
 * Require a specific feature. Returns null if allowed, or an error Response if blocked.
 * Use in Edge Functions:
 *   const blocked = await requireFeature(supabase, userId, 'semanticSearch');
 *   if (blocked) return blocked;
 */
export async function requireFeature(
  supabase: SupabaseClient,
  userId: string,
  feature: 'aiActions' | 'semanticSearch' | 'cloudSync' | 'commits' | 'shareLinks' | 'fullInsights' | 'aiWorkspace',
): Promise<Response | null> {
  const { tier } = await getUserTier(supabase, userId);

  if (tier === 'pro' || tier === 'founding') return null; // all features unlocked

  // Free tier restrictions
  const proOnlyFeatures = ['semanticSearch', 'cloudSync', 'commits', 'shareLinks', 'fullInsights', 'aiWorkspace'];
  if (proOnlyFeatures.includes(feature)) {
    return errorResponse('UPGRADE_REQUIRED', `${feature} requires an Obius Pro subscription`, 403);
  }

  return null;
}

/**
 * Check AI action rate limit. Returns null if allowed, or an error Response if blocked.
 * Increments the counter on success.
 */
export async function requireAIAction(
  supabase: SupabaseClient,
  userId: string,
): Promise<Response | null> {
  // Anonymous users get a small free allowance
  if (userId === 'anonymous') return null;

  const { tier } = await getUserTier(supabase, userId);
  const limit = AI_ACTION_LIMITS[tier];

  // Count today's usage from usage_log
  const todayStart = new Date();
  todayStart.setUTCHours(0, 0, 0, 0);

  const { count, error } = await supabase
    .from('usage_log')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', todayStart.toISOString());

  if (error) {
    console.warn(`[Entitlements] Could not check usage for ${userId}: ${error.message}`);
    return null; // fail open
  }

  if ((count ?? 0) >= limit) {
    return errorResponse(
      'AI_LIMIT_REACHED',
      `You've used all ${limit} AI actions for today. ${tier === 'free' ? 'Upgrade to Pro for 100/day.' : 'Limit resets at midnight UTC.'}`,
      429,
    );
  }

  return null;
}

/**
 * Check if a user can create a new entity of the given type.
 * Returns null if allowed, or an error Response if over limit.
 */
export async function requireEntityCreate(
  supabase: SupabaseClient,
  userId: string,
  entityType: 'note' | 'section',
  noteId?: string,
): Promise<Response | null> {
  const { tier } = await getUserTier(supabase, userId);
  const limits = getLimits(tier);

  if (entityType === 'note') {
    if (limits.maxNotes === null) return null;

    const { count, error } = await supabase
      .from('notes')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .is('deleted_at', null);

    if (error) return null; // fail open
    if ((count ?? 0) >= limits.maxNotes) {
      return errorResponse(
        'NOTE_LIMIT_REACHED',
        `Free plan is limited to ${limits.maxNotes} notes. Upgrade to Pro for unlimited.`,
        403,
      );
    }
  }

  if (entityType === 'section' && noteId && limits.maxSectionsPerNote !== null) {
    const { count, error } = await supabase
      .from('sections')
      .select('*', { count: 'exact', head: true })
      .eq('note_id', noteId)
      .eq('user_id', userId)
      .is('deleted_at', null);

    if (error) return null;
    if ((count ?? 0) >= limits.maxSectionsPerNote) {
      return errorResponse(
        'SECTION_LIMIT_REACHED',
        `Free plan is limited to ${limits.maxSectionsPerNote} sections per note. Upgrade to Pro for unlimited.`,
        403,
      );
    }
  }

  return null;
}

/**
 * Verify entitlement server-side via RevenueCat REST API.
 * Use as a fallback for critical operations where webhook state may be stale.
 */
export async function verifyWithRevenueCat(appUserId: string): Promise<boolean> {
  const apiKey = Deno.env.get('REVENUECAT_API_KEY');
  if (!apiKey) return false;

  try {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
      {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
      },
    );

    if (!res.ok) return false;

    const data = await res.json();
    const entitlement = data?.subscriber?.entitlements?.['Obius Pro'];
    if (!entitlement) return false;

    const expiresDate = entitlement.expires_date;
    if (!expiresDate) return true; // lifetime
    return new Date(expiresDate) > new Date();
  } catch (err) {
    console.error('[Entitlements] RC API check failed:', err);
    return false;
  }
}
