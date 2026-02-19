// OBIUS Deactivate Share Edge Function
// Deactivates a share link so it's no longer publicly accessible

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';

interface DeactivateShareRequest {
  shareLinkId: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    const body: DeactivateShareRequest = await req.json();

    if (!body.shareLinkId) {
      return errorResponse('MISSING_ID', 'shareLinkId is required');
    }

    // Verify ownership
    const { data: shareLink, error: fetchError } = await supabase
      .from('share_links')
      .select('id, user_id')
      .eq('id', body.shareLinkId)
      .single();

    if (fetchError || !shareLink) {
      return errorResponse('NOT_FOUND', 'Share link not found', 404);
    }

    if (shareLink.user_id !== userId) {
      return errorResponse('UNAUTHORIZED', 'You can only deactivate your own share links', 403);
    }

    // Deactivate
    const { error: updateError } = await supabase
      .from('share_links')
      .update({ is_active: false })
      .eq('id', body.shareLinkId);

    if (updateError) {
      console.error('Update error:', updateError);
      return errorResponse('UPDATE_FAILED', 'Failed to deactivate share link', 500);
    }

    return jsonResponse({ success: true });
  } catch (error) {
    if (error.name === 'AuthError') {
      return errorResponse('AUTH_ERROR', error.message, 401);
    }
    console.error('Unexpected error:', error);
    return errorResponse('SERVER_ERROR', 'Internal server error', 500);
  }
});
