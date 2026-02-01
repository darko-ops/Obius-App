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
  Note,
  Section,
} from '../_shared/types.ts';

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

    const accepted: string[] = [];
    const conflicts: ConflictInfo[] = [];

    // Process each operation
    for (const op of operations) {
      try {
        const result = await processOperation(supabase, userId, device_id, op);

        if (result.success) {
          accepted.push(op.operation_id);
        } else if (result.conflict) {
          conflicts.push(result.conflict);
        }
      } catch (error) {
        console.error(`Error processing operation ${op.operation_id}:`, error);
        // Continue processing other operations
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
}

async function processOperation(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  deviceId: string,
  op: SyncOperation
): Promise<ProcessResult> {
  const table = op.entity_type === 'note' ? 'notes' : 'sections';

  // CREATE operation
  if (op.operation === 'create') {
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
        // Entity already exists, treat as update
        return processOperation(supabase, userId, deviceId, {
          ...op,
          operation: 'update',
        });
      }
      console.error(`Create error for ${op.entity_id}:`, error);
      return { success: false };
    }

    // Log to changelog
    await logOperation(supabase, userId, deviceId, op, null, 1);

    return { success: true };
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

      // Last-write-wins resolution
      if (clientTimestamp > serverTimestamp) {
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
          return { success: false };
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
            merged_entity: existing as Note | Section,
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
      return { success: false };
    }

    await logOperation(supabase, userId, deviceId, op, existing.version, existing.version + 1);

    return { success: true };
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
      return { success: true };
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
      return { success: false };
    }

    await logOperation(supabase, userId, deviceId, op, existing.version, existing.version + 1);

    return { success: true };
  }

  return { success: false };
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

// Re-export createServiceClient for logOperation
function createServiceClient() {
  return (await import('../_shared/supabase-client.ts')).createServiceClient();
}
