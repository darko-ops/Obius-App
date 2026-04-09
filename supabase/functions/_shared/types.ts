// OBIUS Shared Types for Edge Functions

export interface Note {
  id: string;
  user_id: string;
  title: string | null;
  ai_title: string | null;
  ai_summary: string | null;
  is_pinned: boolean;
  color_intent: ColorIntent;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  last_modified_by: string | null;
}

export interface Section {
  id: string;
  note_id: string;
  user_id: string;
  content: string;
  content_type: ContentType;
  parent_section_id: string | null;
  order_key: string;
  indent_level: number;
  is_collapsed: boolean;
  color_intent: ColorIntent | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  last_modified_by: string | null;
  embedding: number[] | null;
  embedding_model: string | null;
  embedding_updated_at: string | null;
}

export interface Handle {
  id: string;
  user_id: string;
  name: string;
  display_name: string;
  content: string;
  intent: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  last_modified_by: string | null;
}

export interface Echo {
  id: string;
  user_id: string;
  handle_id: string;
  is_recurring: boolean;
  intervals_json: string | null;
  fire_date: number;
  is_active: boolean;
  next_fire_date: number | null;
  is_alerted: boolean;
  last_acknowledged_at: number | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  last_modified_by: string | null;
}

export interface CalendarMemo {
  id: string;
  user_id: string;
  date_key: string;
  content: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  last_modified_by: string | null;
}

export interface Device {
  id: string;
  user_id: string;
  device_name: string | null;
  platform: Platform;
  app_version: string | null;
  os_version: string | null;
  push_token: string | null;
  last_sync_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface SyncChangelog {
  id: number;
  user_id: string;
  device_id: string;
  entity_type: EntityType;
  entity_id: string;
  operation: Operation;
  payload: Record<string, unknown>;
  previous_version: number | null;
  new_version: number | null;
  client_timestamp: string;
  server_timestamp: string;
}

export interface SyncState {
  id: string;
  user_id: string;
  device_id: string;
  last_sync_timestamp: string;
  last_changelog_id: number | null;
  created_at: string;
  updated_at: string;
}

// Enums
export type ColorIntent = 'default' | 'important' | 'idea' | 'task' | 'reference';
export type ContentType = 'text' | 'checklist' | 'code' | 'quote' | 'image' | 'audio';
export type Platform = 'ios' | 'android' | 'web';
export type EntityType = 'note' | 'section' | 'echo' | 'handle' | 'calendar_memo';
export type Operation = 'create' | 'update' | 'delete';

// Sync Request/Response Types
export interface SyncPullRequest {
  device_id: string;
  last_sync_timestamp: string;
  known_versions?: Record<string, number>; // entity_id -> version
}

export interface SyncPullResponse {
  notes: Note[];
  sections: Section[];
  handles: Handle[];
  echoes: Echo[];
  calendar_memos: CalendarMemo[];
  deleted_note_ids: string[];
  deleted_section_ids: string[];
  deleted_handle_ids: string[];
  deleted_echo_ids: string[];
  deleted_calendar_memo_ids: string[];
  server_timestamp: string;
  has_more: boolean;
}

export interface SyncOperation {
  operation_id: string;
  entity_type: EntityType;
  entity_id: string;
  operation: Operation;
  payload: Record<string, unknown>;
  client_timestamp: string;
  client_version: number;
}

export interface SyncPushRequest {
  device_id: string;
  operations: SyncOperation[];
}

export interface ConflictInfo {
  operation_id: string;
  entity_type: EntityType;
  entity_id: string;
  server_version: number;
  client_version: number;
  resolution: 'server_wins' | 'client_wins' | 'merged';
  merged_entity?: Note | Section | Handle | Echo;
}

export interface AcceptedOp {
  operation_id: string;
  entity_id: string;
  entity_type: string;
  new_version: number;
}

export interface SyncPushResponse {
  accepted: AcceptedOp[];
  conflicts: ConflictInfo[];
  server_timestamp: string;
}

// AI Types
export interface EmbeddingRequest {
  section_id: string;
  content: string;
}

export interface EmbeddingResponse {
  section_id: string;
  success: boolean;
  error?: string;
}

export interface SummaryRequest {
  note_id: string;
}

export interface SummaryResponse {
  note_id: string;
  title: string;
  summary: string;
  success: boolean;
  error?: string;
}

export interface SemanticSearchRequest {
  query: string;
  limit?: number;
  threshold?: number;
}

export interface SemanticSearchResult {
  section_id: string;
  note_id: string;
  content: string;
  similarity: number;
}

export interface SemanticSearchResponse {
  results: SemanticSearchResult[];
  query_embedding?: number[];
}

// Error Types
export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}

// Utility Types
export type WithoutTimestamps<T> = Omit<T, 'created_at' | 'updated_at'>;
export type CreateInput<T> = Omit<T, 'id' | 'created_at' | 'updated_at' | 'version'>;
export type UpdateInput<T> = Partial<Omit<T, 'id' | 'user_id' | 'created_at'>>;
