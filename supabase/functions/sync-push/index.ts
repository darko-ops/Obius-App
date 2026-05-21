// OBIUS Sync Push Edge Function
// Processes client operations and handles conflicts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import type {
  SyncPushRequest,
  SyncPushResponse,
  SyncOperation,
  ConflictInfo,
  AcceptedOp,
  RejectedOp,
  Note,
  Section,
  Handle,
  Echo,
  CalendarMemo,
} from '../_shared/types.ts';
import { requireFeature, requireEntityCreate } from '../_shared/entitlements.ts';

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
    const body: SyncPushRequest = await req.json();
    const { device_id, operations } = body;

    if (!device_id) {
      return errorResponse('MISSING_DEVICE_ID', 'device_id is required');
    }

    if (!operations || !Array.isArray(operations)) {
      return errorResponse('INVALID_OPERATIONS', 'operations must be an array');
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

    const accepted: AcceptedOp[] = [];
    const conflicts: ConflictInfo[] = [];
    const rejected: RejectedOp[] = [];

    // Process each operation
    for (const op of operations) {
      try {
        const result = await processOperation(supabase, userId, device_id, op);

        if (result.success) {
          accepted.push({
            operation_id: op.operation_id,
            entity_id: op.entity_id,
            entity_type: op.entity_type,
            new_version: result.new_version ?? 1,
          });
        } else if (result.conflict) {
          conflicts.push(result.conflict);
        } else {
          // Permanent rejection (CHECK constraint, RLS, unknown entity, etc.).
          // Surface the underlying Postgres error so the client can stop
          // retrying instead of looping on a payload that will never succeed.
          rejected.push({
            operation_id: op.operation_id,
            entity_id: op.entity_id,
            entity_type: op.entity_type,
            code: result.rejected_code ?? 'INTERNAL_ERROR',
            message: result.rejected_message ?? 'Operation rejected by server',
          });
        }
      } catch (error) {
        console.error(`Error processing operation ${op.operation_id}:`, error);
        rejected.push({
          operation_id: op.operation_id,
          entity_id: op.entity_id,
          entity_type: op.entity_type,
          code: 'INTERNAL_ERROR',
          message: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Update device last sync time
    await supabase
      .from('devices')
      .update({ last_sync_at: new Date().toISOString() })
      .eq('id', device_id);

    const response: SyncPushResponse = {
      accepted,
      conflicts,
      rejected,
      server_timestamp: new Date().toISOString(),
    };

    return jsonResponse(response);
  } catch (error) {
    console.error('Sync push error:', error);

    if (error.name === 'AuthError') {
      return errorResponse('UNAUTHORIZED', error.message, 401);
    }

    return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred', 500);
  }
});

interface ProcessResult {
  success: boolean;
  conflict?: ConflictInfo;
  new_version?: number;
  /// Set when `success === false` and the failure is permanent (not a
  /// conflict). Forwarded to the client as a RejectedOp so it can mark the
  /// op done with a logged reason instead of retrying indefinitely.
  rejected_code?: string;
  rejected_message?: string;
}

async function processOperation(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  deviceId: string,
  op: SyncOperation
): Promise<ProcessResult> {
  const tableMap: Record<string, string> = { note: 'notes', section: 'sections', echo: 'echoes', handle: 'handles', calendar_memo: 'calendar_memos' };
  const table = tableMap[op.entity_type] || 'sections';

  // Sanitize boolean fields that may arrive as strings from older clients
  const boolFields = ['is_pinned', 'is_collapsed', 'is_recurring', 'is_active', 'is_alerted'];
  for (const field of boolFields) {
    if (typeof op.payload[field] === 'string') {
      op.payload[field] = op.payload[field] === 'true' || op.payload[field] === '1';
    }
  }

  // Sanitize content_type for sections — ensure valid value
  if (op.entity_type === 'section' && op.payload.content_type) {
    const validTypes = ['text', 'checklist', 'code', 'quote', 'image', 'audio'];
    if (!validTypes.includes(op.payload.content_type as string)) {
      op.payload.content_type = 'text';
    }
  }

  // Strip fields that don't exist in Supabase tables to prevent insert errors
  const noteFields = new Set(['title', 'ai_title', 'ai_summary', 'body', 'body_rich_text', 'interstitial_content', 'interstitial_rich_content', 'is_pinned', 'color_intent', 'module_id', 'module_name', 'module_icon', 'group_name', 'created_at', 'updated_at', 'deleted_at']);
  const sectionFields = new Set(['note_id', 'content', 'content_type', 'parent_section_id', 'order_key', 'indent_level', 'is_collapsed', 'color_intent', 'handle_id', 'created_at', 'updated_at', 'deleted_at']);
  const handleFields = new Set(['name', 'display_name', 'content', 'intent', 'created_at', 'updated_at', 'deleted_at']);
  const echoFields = new Set(['handle_id', 'is_recurring', 'intervals_json', 'fire_date', 'is_active', 'next_fire_date', 'is_alerted', 'last_acknowledged_at', 'created_at', 'updated_at', 'deleted_at']);
  const calendarMemoFields = new Set(['date_key', 'content', 'created_at', 'updated_at', 'deleted_at']);
  const fieldMap: Record<string, Set<string>> = { note: noteFields, section: sectionFields, handle: handleFields, echo: echoFields, calendar_memo: calendarMemoFields };
  const allowedFields = fieldMap[op.entity_type] || sectionFields;
  for (const key of Object.keys(op.payload)) {
    if (!allowedFields.has(key)) {
      delete op.payload[key];
    }
  }

  // CREATE operation
  if (op.operation === 'create') {
    // Enforce entity limits for free-tier users (only notes and sections have limits)
    if (op.entity_type === 'note' || op.entity_type === 'section') {
      const noteId = op.entity_type === 'section' ? (op.payload.note_id as string) : undefined;
      const limitCheck = await requireEntityCreate(supabase, userId, op.entity_type, noteId);
      if (limitCheck) {
        return {
          success: false,
          rejected_code: 'TIER_LIMIT',
          rejected_message: `Free-tier limit reached for ${op.entity_type}`,
        };
      }
    }

    const insertData = {
      ...op.payload,
      id: op.entity_id,
      user_id: userId,
      version: 1,
      last_modified_by: deviceId,
      created_at: op.payload.created_at || new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { error } = await supabase.from(table).insert(insertData);

    if (error) {
      // Check if it's a duplicate key error (entity already exists)
      if (error.code === '23505') {
        // For calendar_memos, the unique constraint is on (user_id, date_key), not just id.
        // A different id can conflict — update the existing row by matching on date_key.
        if (op.entity_type === 'calendar_memo' && op.payload.date_key) {
          const { data: existing } = await supabase
            .from(table)
            .select('id, version')
            .eq('user_id', userId)
            .eq('date_key', op.payload.date_key)
            .is('deleted_at', null)
            .single();

          if (existing) {
            const { error: updateError } = await supabase
              .from(table)
              .update({
                content: op.payload.content,
                version: existing.version + 1,
                last_modified_by: deviceId,
                updated_at: new Date().toISOString(),
              })
              .eq('id', existing.id);

            if (updateError) {
              console.error(`[sync-push] Calendar memo update failed:`, updateError.message);
              return {
                success: false,
                rejected_code: updateError.code ?? 'INTERNAL_ERROR',
                rejected_message: updateError.message ?? 'Calendar memo update failed',
              };
            }
            await logOperation(supabase, userId, deviceId, op, existing.version, existing.version + 1);
            return { success: true, new_version: existing.version + 1 };
          }
        }

        // For other entities, the PK is the same — safe to fall back to update by id
        return processOperation(supabase, userId, deviceId, {
          ...op,
          operation: 'update',
        });
      }
      // Foreign key violation = parent entity missing (e.g. section's note was deleted)
      if (error.code === '23503') {
        console.warn(`[sync-push] FK violation for ${op.entity_type} ${op.entity_id}: ${error.message}`);
        // For sections, the parent note may be legitimately deleted — mark as success to stop retries.
        // For echoes/handles, FK violations are unexpected (no FK constraints) — log and fail so they retry.
        if (op.entity_type === 'section') {
          return { success: true, new_version: 1 };
        }
        return {
          success: false,
          rejected_code: '23503',
          rejected_message: error.message,
        };
      }
      console.error(`[sync-push] Create FAILED for ${op.entity_type} ${op.entity_id}:`, error.code, error.message, 'payload keys:', Object.keys(insertData));
      return {
        success: false,
        rejected_code: error.code ?? 'INTERNAL_ERROR',
        rejected_message: error.message ?? 'Create failed',
      };
    }

    console.log(`[sync-push] Created ${op.entity_type} ${op.entity_id} successfully`);

    // Log to changelog
    await logOperation(supabase, userId, deviceId, op, null, 1);

    return { success: true, new_version: 1 };
  }

  // UPDATE operation
  if (op.operation === 'update') {
    // Fetch current server state
    const { data: existing, error: fetchError } = await supabase
      .from(table)
      .select('*')
      .eq('id', op.entity_id)
      .eq('user_id', userId)
      .single();

    if (fetchError || !existing) {
      // Entity doesn't exist, treat as create
      return processOperation(supabase, userId, deviceId, {
        ...op,
        operation: 'create',
      });
    }

    // Check for conflict
    if (existing.version > op.client_version) {
      // Server has newer version - conflict
      const clientTimestamp = new Date(op.client_timestamp);
      const serverTimestamp = new Date(existing.updated_at);

      // Last-write-wins resolution (also accept if timestamps are very close, e.g. re-sync)
      if (clientTimestamp >= serverTimestamp || (serverTimestamp.getTime() - clientTimestamp.getTime() < 5000)) {
        // Client wins - apply client changes
        const updateData = {
          ...op.payload,
          version: existing.version + 1,
          last_modified_by: deviceId,
          updated_at: new Date().toISOString(),
        };

        const { error: updateError } = await supabase
          .from(table)
          .update(updateData)
          .eq('id', op.entity_id);

        if (updateError) {
          console.error(`Update error for ${op.entity_id}:`, updateError);
          return {
            success: false,
            rejected_code: updateError.code ?? 'INTERNAL_ERROR',
            rejected_message: updateError.message ?? 'Update failed (LWW client-wins path)',
          };
        }

        await logOperation(supabase, userId, deviceId, op, existing.version, existing.version + 1);

        return {
          success: true,
          conflict: {
            operation_id: op.operation_id,
            entity_type: op.entity_type,
            entity_id: op.entity_id,
            server_version: existing.version,
            client_version: op.client_version,
            resolution: 'client_wins',
          },
        };
      } else {
        // Server wins - return current server state
        return {
          success: false,
          conflict: {
            operation_id: op.operation_id,
            entity_type: op.entity_type,
            entity_id: op.entity_id,
            server_version: existing.version,
            client_version: op.client_version,
            resolution: 'server_wins',
            merged_entity: existing as Note | Section | Handle | Echo,
          },
        };
      }
    }

    // No conflict - apply update
    const updateData = {
      ...op.payload,
      version: existing.version + 1,
      last_modified_by: deviceId,
      updated_at: new Date().toISOString(),
    };

    // Don't allow updating certain fields
    delete updateData.id;
    delete updateData.user_id;
    delete updateData.created_at;

    const { error: updateError } = await supabase
      .from(table)
      .update(updateData)
      .eq('id', op.entity_id);

    if (updateError) {
      console.error(`Update error for ${op.entity_id}:`, updateError);
      return {
        success: false,
        rejected_code: updateError.code ?? 'INTERNAL_ERROR',
        rejected_message: updateError.message ?? 'Update failed',
      };
    }

    await logOperation(supabase, userId, deviceId, op, existing.version, existing.version + 1);

    return { success: true, new_version: existing.version + 1 };
  }

  // DELETE operation
  if (op.operation === 'delete') {
    // Soft delete - set deleted_at
    const { data: existing, error: fetchError } = await supabase
      .from(table)
      .select('version')
      .eq('id', op.entity_id)
      .eq('user_id', userId)
      .single();

    if (fetchError || !existing) {
      // Already deleted or doesn't exist
      return { success: true, new_version: 1 };
    }

    const { error: deleteError } = await supabase
      .from(table)
      .update({
        deleted_at: new Date().toISOString(),
        version: existing.version + 1,
        last_modified_by: deviceId,
        updated_at: new Date().toISOString(),
      })
      .eq('id', op.entity_id);

    if (deleteError) {
      console.error(`Delete error for ${op.entity_id}:`, deleteError);
      return {
        success: false,
        rejected_code: deleteError.code ?? 'INTERNAL_ERROR',
        rejected_message: deleteError.message ?? 'Delete failed',
      };
    }

    await logOperation(supabase, userId, deviceId, op, existing.version, existing.version + 1);

    return { success: true, new_version: existing.version + 1 };
  }

  return {
    success: false,
    rejected_code: 'UNKNOWN_OPERATION',
    rejected_message: `Unknown operation type '${op.operation}' for entity '${op.entity_type}'`,
  };
}

async function logOperation(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  deviceId: string,
  op: SyncOperation,
  previousVersion: number | null,
  newVersion: number
): Promise<void> {
  await supabase.from('sync_changelog').insert({
    user_id: userId,
    device_id: deviceId,
    entity_type: op.entity_type,
    entity_id: op.entity_id,
    operation: op.operation,
    payload: op.payload,
    client_timestamp: op.client_timestamp,
    previous_version: previousVersion,
    new_version: newVersion,
  });
}
