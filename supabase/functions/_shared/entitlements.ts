// Server-side entitlement checks
// Uses the subscription_tier column set by the RevenueCat webhook

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

export type SubscriptionTier = 'free' | 'pro' | 'founding';

interface UserTierInfo {
  tier: SubscriptionTier;
  isFoundingMember: boolean;
  expiresAt: string | null;
}

/**
 * Get the subscription tier for a user from the database.
 * Falls back to RevenueCat API if subscription_expires_at has passed.
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
    return { tier: 'free', isFoundingMember: false, expiresAt: null };
  }

  return {
    tier: data.subscription_tier as SubscriptionTier,
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
 * Verify entitlement server-side via RevenueCat REST API.
 * Use this as a fallback or for critical operations where you need
 * a real-time check rather than relying on webhook state.
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

    // Check expiration
    const expiresDate = entitlement.expires_date;
    if (!expiresDate) return true; // lifetime
    return new Date(expiresDate) > new Date();
  } catch (err) {
    console.error('[Entitlements] RC API check failed:', err);
    return false;
  }
}
