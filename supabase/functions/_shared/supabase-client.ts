// Supabase Client Setup for Edge Functions

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// Environment variables (set in Supabase Dashboard)
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

/**
 * Create a Supabase client with service role (bypasses RLS)
 * Use for server-side operations that need full access
 */
export function createServiceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Create a Supabase client with user's JWT token
 * Use for operations that should respect RLS
 */
export function createUserClient(authHeader: string): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Extract and verify JWT from request
 * Returns user ID if valid, throws if invalid
 */
export async function verifyAuth(req: Request): Promise<{ userId: string; client: SupabaseClient }> {
  const authHeader = req.headers.get('Authorization');

  if (!authHeader) {
    throw new AuthError('Missing Authorization header');
  }

  // Extract the bare JWT token
  const token = authHeader.replace('Bearer ', '');

  const client = createUserClient(authHeader);
  // Pass token directly — client.auth.getUser() without a token argument
  // ignores global headers in Supabase JS SDK v2
  const { data: { user }, error } = await client.auth.getUser(token);

  if (error || !user) {
    throw new AuthError('Invalid or expired token');
  }

  return { userId: user.id, client };
}

/**
 * Auth error class
 */
export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AuthError';
  }
}

/**
 * Create JSON response helper
 */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    },
  });
}

/**
 * Create error response helper
 */
export function errorResponse(code: string, message: string, status = 400): Response {
  return jsonResponse({ error: { code, message } }, status);
}

/**
 * CORS preflight response
 */
export function corsResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      'Access-Control-Max-Age': '86400',
    },
  });
}
