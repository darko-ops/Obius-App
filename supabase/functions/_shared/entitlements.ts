// Server-side entitlement checks
// Uses the subscription_tier, subscription_period, and bonus_credits_this_month
// columns set by the RevenueCat webhook (and the iOS client as a fallback).
//
// Unit Economics (post-rework):
//   1 Credit = 1,000 tokens (input + output combined). Caps reset on the 1st of
//   each calendar month, UTC. The Power Pack (`credits_pack_10`) is a
//   *consumable* IAP — each purchase adds 1,000 Credits to the current cycle
//   via `grant_power_pack_credits()`. Users may buy multiple packs per month.
//   The cycle bonus expires when `bonus_credits_month_key` no longer matches
//   the current UTC month.

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { errorResponse } from './supabase-client.ts';

export type SubscriptionTier = 'free' | 'pro' | 'founding';
export type SubscriptionPeriod = 'monthly' | 'annual' | null;

interface UserTierInfo {
  tier: SubscriptionTier;
  period: SubscriptionPeriod;
  /** Power Pack top-ups granted this cycle (already cycle-key validated). */
  bonusCreditsThisMonth: number;
  isFoundingMember: boolean;
  expiresAt: string | null;
}

// 1 Credit = 1,000 tokens (must match iOS Credits.tokensPerCredit)
export const TOKENS_PER_CREDIT = 1_000;

// Per-tier monthly Credit caps (must match iOS TierLimits)
//   - pro_monthly: 200, pro_annual: 250 (annual gets a small bonus)
//   - free: 5 (a taste; conversion not retention)
//   - founding: 200 (matches Pro Monthly)
export const AI_CREDIT_LIMITS = {
  free: 5,
  pro_monthly: 200,
  pro_annual: 250,
  founding: 200,
} as const;

// Power Pack: each consumable purchase adds this many Credits to the cycle.
export const POWER_PACK_CREDITS_PER_PURCHASE = 1_000;

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
 * Resolve the base monthly Credit cap for a (tier, period) combination.
 * Does NOT include the Power Add-on — call `effectiveCreditCap` for that.
 */
export function baseCreditCap(tier: SubscriptionTier, period: SubscriptionPeriod): number {
  if (tier === 'free') return AI_CREDIT_LIMITS.free;
  if (tier === 'founding') return AI_CREDIT_LIMITS.founding;
  // pro
  return period === 'annual' ? AI_CREDIT_LIMITS.pro_annual : AI_CREDIT_LIMITS.pro_monthly;
}

export function effectiveCreditCap(info: UserTierInfo): number {
  return baseCreditCap(info.tier, info.period) + info.bonusCreditsThisMonth;
}

/** 'YYYY-MM' in UTC — must match the iOS `currentMonthKey()` format. */
export function currentMonthKey(): string {
  const d = new Date();
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

/**
 * Get the subscription tier (+ period + cycle bonus) for a user from the
 * database. The bonus is cycle-key validated: if the stored
 * `bonus_credits_month_key` doesn't match the current UTC month, the bonus
 * is reported as 0 (the cycle rolled over and the next webhook write or
 * client purchase will reset both fields together).
 */
export async function getUserTier(
  supabase: SupabaseClient,
  userId: string,
): Promise<UserTierInfo> {
  const { data, error } = await supabase
    .from('user_profiles')
    .select('subscription_tier, subscription_period, bonus_credits_this_month, bonus_credits_month_key, is_founding_member, subscription_expires_at')
    .eq('id', userId)
    .single();

  if (error || !data) {
    console.warn(`[Entitlements] Could not fetch tier for ${userId}: ${error?.message}`);
    return { tier: 'free', period: null, bonusCreditsThisMonth: 0, isFoundingMember: false, expiresAt: null };
  }

  let tier = data.subscription_tier as SubscriptionTier;
  let period = (data.subscription_period ?? null) as SubscriptionPeriod;

  // Check if subscription has expired (webhook may have been delayed)
  if (tier !== 'free' && data.subscription_expires_at) {
    const expiresAt = new Date(data.subscription_expires_at);
    if (expiresAt < new Date()) {
      // Expired — founding members keep access, others revert
      tier = data.is_founding_member ? 'founding' : 'free';
      // Neither founding nor free has a monthly/annual period
      period = null;
    }
  }

  if (tier !== 'pro') period = null;

  const storedKey = (data.bonus_credits_month_key ?? null) as string | null;
  const rawBonus = Number(data.bonus_credits_this_month ?? 0);
  const cycleBonus = storedKey === currentMonthKey() ? Math.max(0, rawBonus) : 0;

  return {
    tier,
    period,
    bonusCreditsThisMonth: cycleBonus,
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

/** Start of the current calendar month, UTC, as ISO string. */
function monthStartIso(): string {
  const now = new Date();
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1, 0, 0, 0, 0));
  return start.toISOString();
}

/**
 * Check AI credit rate limit. Returns null if allowed, or an error Response if blocked.
 * Cap window: the current calendar month, UTC.
 */
export async function requireAIAction(
  supabase: SupabaseClient,
  userId: string,
): Promise<Response | null> {
  // Anonymous users get a small free allowance
  if (userId === 'anonymous') return null;

  const info = await getUserTier(supabase, userId);
  const cap = effectiveCreditCap(info);

  const tokensUsed = await sumMonthTokens(supabase, userId);
  const creditsUsed = Math.floor(tokensUsed / TOKENS_PER_CREDIT);

  if (creditsUsed >= cap) {
    const upgradeHint =
      info.tier === 'free'
        ? 'Upgrade to Pro for 200 Credits/month.'
        : 'Grab a Power Pack for +1,000 Credits, or wait for the 1st-of-month refill.';

    return errorResponse(
      'AI_LIMIT_REACHED',
      `You've used all ${cap} of your AI Credits this month. ${upgradeHint}`,
      429,
    );
  }

  return null;
}

/** Sum input + output tokens for the current month, UTC. */
async function sumMonthTokens(supabase: SupabaseClient, userId: string): Promise<number> {
  const since = monthStartIso();
  const { data, error } = await supabase
    .from('usage_log')
    .select('input_tokens, output_tokens')
    .eq('user_id', userId)
    .gte('created_at', since);

  if (error) {
    console.warn(`[Entitlements] Could not check usage for ${userId}: ${error.message}`);
    return 0; // fail open
  }

  return (data ?? []).reduce(
    (sum: number, row: { input_tokens: number; output_tokens: number }) => sum + row.input_tokens + row.output_tokens,
    0,
  );
}

/**
 * Get this month's total Credit usage for a user (rounded down to whole Credits).
 */
export async function getCreditsUsedThisMonth(
  supabase: SupabaseClient,
  userId: string,
): Promise<number> {
  const tokens = await sumMonthTokens(supabase, userId);
  return Math.floor(tokens / TOKENS_PER_CREDIT);
}

/**
 * Backwards-compatible alias. Returns this month's raw token total.
 * Prefer `getCreditsUsedThisMonth` for new code.
 */
export async function getTokensUsedThisMonth(
  supabase: SupabaseClient,
  userId: string,
): Promise<number> {
  return await sumMonthTokens(supabase, userId);
}

/**
 * Check if a user can create a new entity of the given type.
 * Returns null if allowed, or an error Response if over limit.
 */
export async function requireEntityCreate(
  supabase: SupabaseClient,
  userId: string,
  entityType: string,
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
