// OBIUS Generate Summary Edge Function
// Creates AI-generated titles and summaries for notes using Claude

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import {
  generateNoteSummary,
  refineTitle,
  GEMINI_PRO_MODEL,
} from '../_shared/gemini-client.ts';
import type { SummaryRequest, SummaryResponse } from '../_shared/types.ts';
import { requireAIAction } from '../_shared/entitlements.ts';
import { logRoutedUsage } from '../_shared/model-router.ts';

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    // Verify authentication
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    // Enforce AI action rate limit
    const blocked = await requireAIAction(supabase, userId);
    if (blocked) return blocked;

    // Parse request
    const body: SummaryRequest & { refine_title?: boolean; current_title?: string } = await req.json();
    const { note_id, refine_title: shouldRefineTitle, current_title } = body;

    if (!note_id) {
      return errorResponse('MISSING_NOTE_ID', 'note_id is required');
    }

    // Fetch note and verify ownership
    const { data: note, error: noteError } = await supabase
      .from('notes')
      .select('id, title, user_id')
      .eq('id', note_id)
      .eq('user_id', userId)
      .single();

    if (noteError || !note) {
      return errorResponse('NOTE_NOT_FOUND', 'Note not found or unauthorized', 404);
    }

    // Fetch all sections for this note
    const { data: sections, error: sectionsError } = await supabase
      .from('sections')
      .select('content, order_key')
      .eq('note_id', note_id)
      .eq('user_id', userId)
      .is('deleted_at', null)
      .order('order_key', { ascending: true });

    if (sectionsError) {
      console.error('Error fetching sections:', sectionsError);
      return errorResponse('DB_ERROR', 'Failed to fetch sections', 500);
    }

    // Combine section content
    const fullContent = sections?.map(s => s.content).join('\n\n') || '';

    if (!fullContent.trim()) {
      return errorResponse('EMPTY_NOTE', 'Note has no content to summarize');
    }

    let title: string;
    let summary: string;

    if (shouldRefineTitle && current_title) {
      // Refine existing title
      title = await refineTitle(current_title, fullContent);
      summary = ''; // Don't generate summary when just refining title
    } else {
      // Generate new title and summary
      const result = await generateNoteSummary(fullContent);
      title = result.title;
      summary = result.summary;
    }

    // Update note with AI-generated content
    const updateData: Record<string, unknown> = {
      ai_title: title,
      updated_at: new Date().toISOString(),
    };

    if (summary) {
      updateData.ai_summary = summary;
    }

    const { error: updateError } = await supabase
      .from('notes')
      .update(updateData)
      .eq('id', note_id)
      .eq('user_id', userId);

    if (updateError) {
      console.error('Error updating note:', updateError);
      return errorResponse('DB_ERROR', 'Failed to save summary', 500);
    }

    const response: SummaryResponse = {
      note_id,
      title,
      summary,
      success: true,
    };

    return jsonResponse({
      ...response,
      model: GEMINI_PRO_MODEL,
      provider: 'gemini',
    });
  } catch (error) {
    console.error('Generate summary error:', error);

    if (error.name === 'AuthError') {
      return errorResponse('UNAUTHORIZED', error.message, 401);
    }

    return errorResponse('INTERNAL_ERROR', error.message || 'An unexpected error occurred', 500);
  }
});
