// OBIUS Generate Embedding Edge Function
// Creates embeddings for sections using OpenAI

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import {
  generateEmbedding,
  generateEmbeddings,
  EMBEDDING_MODEL,
} from '../_shared/openai-client.ts';
import type { EmbeddingRequest, EmbeddingResponse } from '../_shared/types.ts';
import { requireFeature } from '../_shared/entitlements.ts';

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    // Verify authentication
    const { userId } = await verifyAuth(req);
    const supabase = createServiceClient();

    // Embeddings power semantic search — require Pro
    const blocked = await requireFeature(supabase, userId, 'semanticSearch');
    if (blocked) return blocked;

    // Parse request
    const body = await req.json();

    // Support both single and batch requests
    const requests: EmbeddingRequest[] = Array.isArray(body) ? body : [body];

    if (requests.length === 0) {
      return errorResponse('INVALID_REQUEST', 'At least one section required');
    }

    if (requests.length > 100) {
      return errorResponse('TOO_MANY_REQUESTS', 'Maximum 100 sections per request');
    }

    // Validate all sections belong to user
    const sectionIds = requests.map(r => r.section_id);
    const { data: sections, error: sectionsError } = await supabase
      .from('sections')
      .select('id, content')
      .eq('user_id', userId)
      .in('id', sectionIds);

    if (sectionsError) {
      console.error('Error fetching sections:', sectionsError);
      return errorResponse('DB_ERROR', 'Failed to fetch sections', 500);
    }

    // Map sections by ID
    const sectionMap = new Map(sections?.map(s => [s.id, s]) || []);

    // Filter to valid sections with content
    const validRequests = requests.filter(r => {
      const section = sectionMap.get(r.section_id);
      return section && (r.content || section.content)?.trim();
    });

    if (validRequests.length === 0) {
      return jsonResponse({
        results: requests.map(r => ({
          section_id: r.section_id,
          success: false,
          error: 'Section not found or empty',
        })),
      });
    }

    // Get content for each section
    const contents = validRequests.map(r => {
      const section = sectionMap.get(r.section_id);
      return r.content || section?.content || '';
    });

    // Generate embeddings in batch
    const embeddings = await generateEmbeddings(contents);

    // Update sections with embeddings
    const results: EmbeddingResponse[] = [];
    const now = new Date().toISOString();

    for (let i = 0; i < validRequests.length; i++) {
      const request = validRequests[i];
      const embedding = embeddings[i];

      try {
        const { error: updateError } = await supabase
          .from('sections')
          .update({
            embedding: embedding.embedding,
            embedding_model: EMBEDDING_MODEL,
            embedding_updated_at: now,
          })
          .eq('id', request.section_id)
          .eq('user_id', userId);

        if (updateError) {
          console.error(`Error updating section ${request.section_id}:`, updateError);
          results.push({
            section_id: request.section_id,
            success: false,
            error: 'Failed to save embedding',
          });
        } else {
          results.push({
            section_id: request.section_id,
            success: true,
          });
        }
      } catch (error) {
        console.error(`Error processing section ${request.section_id}:`, error);
        results.push({
          section_id: request.section_id,
          success: false,
          error: error.message,
        });
      }
    }

    // Add results for invalid requests
    for (const request of requests) {
      if (!results.find(r => r.section_id === request.section_id)) {
        results.push({
          section_id: request.section_id,
          success: false,
          error: 'Section not found or empty',
        });
      }
    }

    return jsonResponse({
      results,
      model: EMBEDDING_MODEL,
    });
  } catch (error) {
    console.error('Generate embedding error:', error);

    if (error.name === 'AuthError') {
      return errorResponse('UNAUTHORIZED', error.message, 401);
    }

    return errorResponse('INTERNAL_ERROR', error.message || 'An unexpected error occurred', 500);
  }
});
