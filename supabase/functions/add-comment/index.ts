// OBIUS Add Comment Edge Function
// Adds a comment (Handshake) to shared content

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

interface AddCommentRequest {
  shareLinkId: string;
  body: string;
  parentCommentId?: string;
}

async function computeSealedHash(
  supabase: ReturnType<typeof createServiceClient>,
  shareLinkId: string,
  originalContent: string | null,
): Promise<string | null> {
  if (!originalContent) return null;

  // Get all existing comments for this share link
  const { data: existingComments } = await supabase
    .from('comments')
    .select('body, created_at')
    .eq('share_link_id', shareLinkId)
    .is('deleted_at', null)
    .order('created_at', { ascending: true });

  // Build the hash input: original content + all comment bodies
  const parts = [originalContent];
  for (const c of existingComments || []) {
    parts.push(c.body);
  }

  const input = parts.join('\n---\n');
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  return `sha256:${hashHex}`;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const { userId, client } = await verifyAuth(req);
    const supabase = createServiceClient();

    const body: AddCommentRequest = await req.json();

    if (!body.shareLinkId || !body.body?.trim()) {
      return errorResponse('INVALID_INPUT', 'shareLinkId and body are required');
    }

    // Verify share link exists and is active
    const { data: shareLink, error: linkError } = await supabase
      .from('share_links')
      .select('id, share_type, commit_content, is_active')
      .eq('id', body.shareLinkId)
      .single();

    if (linkError || !shareLink) {
      return errorResponse('NOT_FOUND', 'Share link not found', 404);
    }

    if (!shareLink.is_active) {
      return errorResponse('INACTIVE', 'This share link is no longer active');
    }

    // Get user display name
    const { data: profile } = await supabase
      .from('user_profiles')
      .select('display_name')
      .eq('id', userId)
      .single();

    const displayName = profile?.display_name || null;

    // For commit shares, compute sealed hash
    let sealedHash: string | null = null;
    if (shareLink.share_type === 'commit' && shareLink.commit_content) {
      sealedHash = await computeSealedHash(
        supabase,
        body.shareLinkId,
        JSON.stringify(shareLink.commit_content),
      );
    }

    // Insert comment
    const { data: comment, error: insertError } = await supabase
      .from('comments')
      .insert({
        share_link_id: body.shareLinkId,
        user_id: userId,
        user_display_name: displayName,
        parent_comment_id: body.parentCommentId || null,
        body: body.body.trim(),
        sealed_commit_hash: sealedHash,
      })
      .select('id, user_id, user_display_name, body, created_at, sealed_commit_hash')
      .single();

    if (insertError) {
      console.error('Insert error:', insertError);
      return errorResponse('INSERT_FAILED', 'Failed to post comment', 500);
    }

    return jsonResponse({
      success: true,
      comment: {
        id: comment.id,
        userId: comment.user_id,
        userDisplayName: comment.user_display_name,
        body: comment.body,
        createdAt: new Date(comment.created_at).getTime(),
        sealedCommitHash: comment.sealed_commit_hash,
      },
      sealedCommitHash: sealedHash,
    });
  } catch (error) {
    if (error.name === 'AuthError') {
      return errorResponse('AUTH_ERROR', error.message, 401);
    }
    console.error('Unexpected error:', error);
    return errorResponse('SERVER_ERROR', 'Internal server error', 500);
  }
});
