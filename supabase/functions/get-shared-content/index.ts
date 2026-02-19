// OBIUS Get Shared Content Edge Function
// Retrieves shared content by slug for public viewing

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

interface GetSharedContentRequest {
  slug: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    // No auth required — shared content is public
    const supabase = createServiceClient();
    const body: GetSharedContentRequest = await req.json();

    if (!body.slug) {
      return errorResponse('MISSING_SLUG', 'slug is required');
    }

    // Look up the share link
    const { data: shareLink, error: linkError } = await supabase
      .from('share_links')
      .select('*')
      .eq('slug', body.slug)
      .eq('is_active', true)
      .is('deleted_at', null)
      .single();

    if (linkError || !shareLink) {
      return errorResponse('NOT_FOUND', 'Shared content not found or link is inactive', 404);
    }

    // Check expiration
    if (shareLink.expires_at && new Date(shareLink.expires_at) < new Date()) {
      return errorResponse('EXPIRED', 'This share link has expired', 410);
    }

    // Increment view count (fire and forget)
    supabase
      .from('share_links')
      .update({ view_count: (shareLink.view_count || 0) + 1 })
      .eq('id', shareLink.id)
      .then(() => {});

    // Fetch comments
    const { data: comments } = await supabase
      .from('comments')
      .select('id, user_id, user_display_name, body, created_at, sealed_commit_hash')
      .eq('share_link_id', shareLink.id)
      .is('deleted_at', null)
      .order('created_at', { ascending: true });

    const formattedComments = (comments || []).map((c: Record<string, unknown>) => ({
      id: c.id,
      userId: c.user_id,
      userDisplayName: c.user_display_name,
      body: c.body,
      createdAt: new Date(c.created_at as string).getTime(),
      sealedCommitHash: c.sealed_commit_hash,
    }));

    if (shareLink.share_type === 'live') {
      // Fetch live note + sections
      const { data: note } = await supabase
        .from('notes')
        .select('id, title, body')
        .eq('id', shareLink.note_id)
        .is('deleted_at', null)
        .single();

      if (!note) {
        return errorResponse('NOTE_DELETED', 'The shared note has been deleted', 404);
      }

      const { data: sections } = await supabase
        .from('sections')
        .select('id, content, content_type, order_key, indent_level')
        .eq('note_id', shareLink.note_id)
        .is('deleted_at', null)
        .order('order_key', { ascending: true });

      const formattedSections = (sections || []).map((s: Record<string, unknown>) => ({
        id: s.id,
        content: s.content,
        contentType: s.content_type,
        orderKey: s.order_key,
        indentLevel: s.indent_level,
      }));

      return jsonResponse({
        success: true,
        shareType: 'live',
        note: {
          id: note.id,
          title: note.title,
          body: note.body || '',
        },
        sections: formattedSections,
        comments: formattedComments,
        viewCount: shareLink.view_count + 1,
      });
    } else {
      // Return commit content
      return jsonResponse({
        success: true,
        shareType: 'commit',
        commitContent: shareLink.commit_content
          ? JSON.stringify(shareLink.commit_content)
          : null,
        commitName: shareLink.commit_name,
        comments: formattedComments,
        viewCount: shareLink.view_count + 1,
      });
    }
  } catch (error) {
    console.error('Unexpected error:', error);
    return errorResponse('SERVER_ERROR', 'Internal server error', 500);
  }
});
