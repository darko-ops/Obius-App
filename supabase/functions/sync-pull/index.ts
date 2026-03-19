// OBIUS Sync Pull Edge Function
// Fetches changes since last sync for a device

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import type {
  SyncPullRequest,
  SyncPullResponse,
  Note,
  Section,
} from '../_shared/types.ts';
import { requireFeature } from '../_shared/entitlements.ts';

const MAX_ITEMS_PER_SYNC = 500;

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    // Verify authentication
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    // Parse request
    const body: SyncPullRequest = await req.json();
    const { device_id, last_sync_timestamp, known_versions } = body;

    if (!device_id) {
      return errorResponse('MISSING_DEVICE_ID', 'device_id is required');
    }

    // Validate device belongs to user
    const { data: device, error: deviceError } = await supabase
      .from('devices')
      .select('id')
      .eq('id', device_id)
      .eq('user_id', userId)
      .single();

    if (deviceError || !device) {
      return errorResponse('INVALID_DEVICE', 'Device not found or unauthorized', 403);
    }

    // Cloud sync requires Pro
    const syncGate = await requireFeature(supabase, userId, 'cloudSync');
    if (syncGate) return syncGate;

    // Parse timestamp
    const sinceTimestamp = last_sync_timestamp
      ? new Date(last_sync_timestamp)
      : new Date(0);

    // Fetch updated notes
    const { data: notes, error: notesError } = await supabase
      .from('notes')
      .select('*')
      .eq('user_id', userId)
      .gt('updated_at', sinceTimestamp.toISOString())
      .is('deleted_at', null)
      .order('updated_at', { ascending: true })
      .limit(MAX_ITEMS_PER_SYNC);

    if (notesError) {
      console.error('Error fetching notes:', notesError);
      return errorResponse('DB_ERROR', 'Failed to fetch notes', 500);
    }

    // Fetch updated sections
    const { data: sections, error: sectionsError } = await supabase
      .from('sections')
      .select('*')
      .eq('user_id', userId)
      .gt('updated_at', sinceTimestamp.toISOString())
      .is('deleted_at', null)
      .order('updated_at', { ascending: true })
      .limit(MAX_ITEMS_PER_SYNC);

    if (sectionsError) {
      console.error('Error fetching sections:', sectionsError);
      return errorResponse('DB_ERROR', 'Failed to fetch sections', 500);
    }

    // Fetch deleted items from changelog
    const { data: deletions, error: deletionsError } = await supabase
      .from('sync_changelog')
      .select('entity_type, entity_id')
      .eq('user_id', userId)
      .eq('operation', 'delete')
      .gt('server_timestamp', sinceTimestamp.toISOString())
      .neq('device_id', device_id); // Don't send back deletions from same device

    if (deletionsError) {
      console.error('Error fetching deletions:', deletionsError);
      return errorResponse('DB_ERROR', 'Failed to fetch deletions', 500);
    }

    // Separate deletions by type
    const deletedNoteIds: string[] = [];
    const deletedSectionIds: string[] = [];

    for (const deletion of deletions || []) {
      if (deletion.entity_type === 'note') {
        deletedNoteIds.push(deletion.entity_id);
      } else if (deletion.entity_type === 'section') {
        deletedSectionIds.push(deletion.entity_id);
      }
    }

    // Filter out items that client already has at same version
    const filteredNotes = filterByVersion(notes || [], known_versions);
    const filteredSections = filterByVersion(sections || [], known_versions);

    // Check if there are more items to sync
    const hasMore =
      (notes?.length || 0) >= MAX_ITEMS_PER_SYNC ||
      (sections?.length || 0) >= MAX_ITEMS_PER_SYNC;

    // Update device last sync time
    await supabase
      .from('devices')
      .update({ last_sync_at: new Date().toISOString() })
      .eq('id', device_id);

    // Build response
    const response: SyncPullResponse = {
      notes: filteredNotes as Note[],
      sections: filteredSections.map(s => ({
        ...s,
        // Don't send embedding vector to client (too large)
        embedding: null,
      })) as Section[],
      deleted_note_ids: deletedNoteIds,
      deleted_section_ids: deletedSectionIds,
      server_timestamp: new Date().toISOString(),
      has_more: hasMore,
    };

    return jsonResponse(response);
  } catch (error) {
    console.error('Sync pull error:', error);

    if (error.name === 'AuthError') {
      return errorResponse('UNAUTHORIZED', error.message, 401);
    }

    return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred', 500);
  }
});

/**
 * Filter out items that client already has at the same version
 */
function filterByVersion<T extends { id: string; version: number }>(
  items: T[],
  knownVersions?: Record<string, number>
): T[] {
  if (!knownVersions || Object.keys(knownVersions).length === 0) {
    return items;
  }

  return items.filter(item => {
    const knownVersion = knownVersions[item.id];
    // Include if client doesn't know about it or has older version
    return knownVersion === undefined || knownVersion < item.version;
  });
}
