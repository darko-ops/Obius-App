// OBIUS Delete Account Edge Function
// Permanently deletes the authenticated user's account and all associated data.
//
// Server-side flow:
//   1. Recursively remove the user's objects from storage buckets
//      (profile-images, note-media). Files are stored under <user_id>/...
//   2. Delete the auth user via the admin API. All public.* tables FK to
//      auth.users (or to user_profiles, which itself FKs to auth.users) with
//      ON DELETE CASCADE, so this single delete tears down every row the user
//      owns: notes, sections, handles, echoes, devices, sync_changelog,
//      share_links, comments, calendar_memos, usage_log, subscription_events,
//      user_profiles, etc.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

const STORAGE_BUCKETS = ['profile-images', 'note-media'] as const;

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

    // 2. Delete the auth user — public.* rows cascade via FK ON DELETE CASCADE.
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
