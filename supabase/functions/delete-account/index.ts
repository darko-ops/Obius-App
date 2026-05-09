// OBIUS Delete Account Edge Function
// Permanently deletes the authenticated user's account and all associated data.
//
// Server-side flow:
//   1. Recursively remove the user's objects from storage buckets
//      (profile-images, note-media). Files are stored under <user_id>/...
//   2. Explicitly delete from tables whose FK to auth.users is missing
//      ON DELETE CASCADE — usage_log and subscription_events. Without this
//      step, auth.admin.deleteUser fails with FK-violation 500s for any user
//      who's used AI or had a subscription event recorded.
//   3. Delete the auth user via the admin API. The remaining public.* tables
//      cascade automatically (most go through user_profiles, which itself
//      FKs auth.users with ON DELETE CASCADE).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

const STORAGE_BUCKETS = ['profile-images', 'note-media'] as const;

// Tables whose FK to auth.users is NOT ON DELETE CASCADE — must be cleared
// explicitly before calling auth.admin.deleteUser.
const NON_CASCADING_TABLES = ['usage_log', 'subscription_events'] as const;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return corsResponse();

  try {
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    // 1. Clear storage objects scoped under <userId>/...
    for (const bucket of STORAGE_BUCKETS) {
      try {
        const { data: files, error: listError } = await supabase.storage
          .from(bucket)
          .list(userId, { limit: 1000 });

        if (listError) {
          console.error(`[delete-account] List failed (${bucket}):`, listError);
          continue;
        }

        if (files && files.length > 0) {
          const paths = files.map((f) => `${userId}/${f.name}`);
          const { error: removeError } = await supabase.storage
            .from(bucket)
            .remove(paths);
          if (removeError) {
            console.error(`[delete-account] Remove failed (${bucket}):`, removeError);
          }
        }
      } catch (e) {
        console.error(`[delete-account] Unexpected error clearing ${bucket}:`, e);
      }
    }

    // 2. Manually clear tables whose FK to auth.users is not ON DELETE CASCADE.
    for (const table of NON_CASCADING_TABLES) {
      const { error } = await supabase.from(table).delete().eq('user_id', userId);
      if (error) {
        console.error(`[delete-account] Failed to clear ${table}:`, error);
        return errorResponse(
          'PRECASCADE_DELETE_FAILED',
          `Could not clear ${table}: ${error.message}`,
          500,
        );
      }
    }

    // 3. Delete the auth user — remaining public.* rows cascade via FK ON DELETE CASCADE.
    const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error('[delete-account] Auth delete failed:', deleteError);
      return errorResponse('DELETE_FAILED', deleteError.message, 500);
    }

    console.log(`[delete-account] Deleted user ${userId}`);
    return jsonResponse({ success: true });
  } catch (error) {
    if ((error as Error).name === 'AuthError') {
      return errorResponse('AUTH_ERROR', (error as Error).message, 401);
    }
    console.error('[delete-account] Unexpected error:', error);
    return errorResponse('SERVER_ERROR', 'Internal server error', 500);
  }
});
