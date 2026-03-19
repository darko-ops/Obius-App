// OBIUS Create Share Edge Function
// Creates a new share link for a note (live) or commit (snapshot)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import { requireFeature } from '../_shared/entitlements.ts';

interface CreateShareRequest {
  shareType: 'live' | 'commit';
  noteId?: string;
  commitHash?: string;
  commitName?: string;
  commitContent?: string; // JSON string of .obx content
}

function generateSlug(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let slug = '';
  for (let i = 0; i < 8; i++) {
    slug += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return slug;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    // Share links require Pro
    const shareGate = await requireFeature(supabase, userId, 'shareLinks');
    if (shareGate) return shareGate;

    const body: CreateShareRequest = await req.json();

    // Validate
    if (!body.shareType || !['live', 'commit'].includes(body.shareType)) {
      return errorResponse('INVALID_TYPE', 'shareType must be "live" or "commit"');
    }

    if (body.shareType === 'live' && !body.noteId) {
      return errorResponse('MISSING_NOTE', 'noteId is required for live shares');
    }

    if (body.shareType === 'commit' && !body.commitHash) {
      return errorResponse('MISSING_HASH', 'commitHash is required for commit shares');
    }

    // For live shares, verify the note belongs to the user
    if (body.shareType === 'live') {
      const { data: note, error: noteError } = await supabase
        .from('notes')
        .select('id, user_id')
        .eq('id', body.noteId)
        .single();

      if (noteError || !note) {
        return errorResponse('NOTE_NOT_FOUND', 'Note not found');
      }

      if (note.user_id !== userId) {
        return errorResponse('UNAUTHORIZED', 'You can only share your own notes', 403);
      }
    }

    // Generate unique slug (retry on collision)
    let slug = generateSlug();
    let retries = 3;
    while (retries > 0) {
      const { data: existing } = await supabase
        .from('share_links')
        .select('id')
        .eq('slug', slug)
        .single();

      if (!existing) break;
      slug = generateSlug();
      retries--;
    }

    // Parse commit content if provided
    let commitContent = null;
    if (body.commitContent) {
      try {
        commitContent = JSON.parse(body.commitContent);
      } catch {
        return errorResponse('INVALID_CONTENT', 'commitContent must be valid JSON');
      }
    }

    // Insert share link
    const { data: shareLink, error: insertError } = await supabase
      .from('share_links')
      .insert({
        slug,
        user_id: userId,
        share_type: body.shareType,
        note_id: body.noteId || null,
        commit_hash: body.commitHash || null,
        commit_name: body.commitName || null,
        commit_content: commitContent,
      })
      .select('id, slug')
      .single();

    if (insertError) {
      console.error('Insert error:', insertError);
      return errorResponse('INSERT_FAILED', 'Failed to create share link', 500);
    }

    return jsonResponse({
      success: true,
      shareLink: {
        id: shareLink.id,
        slug: shareLink.slug,
      },
    });
  } catch (error) {
    if (error.name === 'AuthError') {
      return errorResponse('AUTH_ERROR', error.message, 401);
    }
    console.error('Unexpected error:', error);
    return errorResponse('SERVER_ERROR', 'Internal server error', 500);
  }
});
