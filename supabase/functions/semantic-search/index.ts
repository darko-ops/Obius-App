// OBIUS Semantic Search Edge Function
// Searches sections using vector similarity

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import { generateEmbedding, EMBEDDING_MODEL } from '../_shared/openai-client.ts';
import type {
  SemanticSearchRequest,
  SemanticSearchResponse,
  SemanticSearchResult,
} from '../_shared/types.ts';
import { requireFeature } from '../_shared/entitlements.ts';

const DEFAULT_LIMIT = 20;
const DEFAULT_THRESHOLD = 0.7;
const MAX_LIMIT = 100;

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    // Verify authentication
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    // Require Pro for semantic search
    const blocked = await requireFeature(supabase, userId, 'semanticSearch');
    if (blocked) return blocked;

    // Parse request
    const body: SemanticSearchRequest = await req.json();
    const {
      query,
      limit = DEFAULT_LIMIT,
      threshold = DEFAULT_THRESHOLD,
    } = body;

    if (!query || !query.trim()) {
      return errorResponse('MISSING_QUERY', 'query is required');
    }

    const actualLimit = Math.min(Math.max(1, limit), MAX_LIMIT);
    const actualThreshold = Math.min(Math.max(0, threshold), 1);

    // Generate embedding for query
    const { embedding: queryEmbedding } = await generateEmbedding(query);

    // Search using pgvector
    const { data: results, error: searchError } = await supabase.rpc(
      'search_sections_semantic',
      {
        query_embedding: queryEmbedding,
        match_threshold: actualThreshold,
        match_count: actualLimit,
        p_user_id: userId,
      }
    );

    if (searchError) {
      console.error('Semantic search error:', searchError);
      return errorResponse('SEARCH_ERROR', 'Search failed', 500);
    }

    // Format results
    const searchResults: SemanticSearchResult[] = (results || []).map(
      (r: { section_id: string; note_id: string; content: string; similarity: number }) => ({
        section_id: r.section_id,
        note_id: r.note_id,
        content: r.content,
        similarity: r.similarity,
      })
    );

    // Fetch note titles for context
    if (searchResults.length > 0) {
      const noteIds = [...new Set(searchResults.map(r => r.note_id))];
      const { data: notes } = await supabase
        .from('notes')
        .select('id, title, ai_title')
        .in('id', noteIds);

      if (notes) {
        const noteMap = new Map(notes.map(n => [n.id, n]));
        for (const result of searchResults) {
          const note = noteMap.get(result.note_id);
          if (note) {
            (result as SemanticSearchResult & { note_title?: string }).note_title =
              note.title || note.ai_title || 'Untitled';
          }
        }
      }
    }

    const response: SemanticSearchResponse = {
      results: searchResults,
    };

    return jsonResponse({
      ...response,
      query,
      model: EMBEDDING_MODEL,
      threshold: actualThreshold,
      limit: actualLimit,
    });
  } catch (error) {
    console.error('Semantic search error:', error);

    if (error.name === 'AuthError') {
      return errorResponse('UNAUTHORIZED', error.message, 401);
    }

    return errorResponse('INTERNAL_ERROR', error.message || 'An unexpected error occurred', 500);
  }
});
