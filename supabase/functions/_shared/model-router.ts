// Model Router — Orchestrates AI calls across providers.
//
// Each Obius AI action is assigned a ROLE that maps to the best provider/model:
//
//   Architect      → Claude Sonnet   — complex tool-calling & reasoning
//   Conversationalist → Claude Haiku — fast, natural dialogue
//   Extractor      → Gemini Flash    — structured extraction (titles, tags, entities, echoes)
//   Synthesizer    → Gemini Pro      — long-context summarization
//   Encoder        → OpenAI          — embeddings (unchanged, not routed here)

import * as anthropic from './anthropic-client.ts';
import * as gemini from './gemini-client.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// ---------- Types ----------

export type AIRole =
  | 'architect'
  | 'conversationalist'
  | 'extractor'
  | 'synthesizer';

export type AIProvider = 'anthropic' | 'gemini';

export interface RouteConfig {
  role: AIRole;
  provider: AIProvider;
  model: string;
}

export interface RoutedResponse {
  content: string;
  provider: AIProvider;
  model: string;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
}

export interface RoutedRawResponse {
  content: unknown[];
  provider: AIProvider;
  model: string;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
  stop_reason: string;
}

// ---------- Route map ----------

const ROUTE_MAP: Record<string, RouteConfig> = {
  // Architect — tool-calling workspace AI
  send_with_tools: {
    role: 'architect',
    provider: 'anthropic',
    model: 'claude-sonnet-4-20250514',
  },
  // Conversationalist — fast chat
  send_chat: {
    role: 'conversationalist',
    provider: 'anthropic',
    model: 'claude-haiku-4-5-20251001',
  },
  // Extractor — structured extraction tasks (Gemini Flash)
  generate_title: {
    role: 'extractor',
    provider: 'gemini',
    model: gemini.GEMINI_FLASH_MODEL,
  },
  generate_tags: {
    role: 'extractor',
    provider: 'gemini',
    model: gemini.GEMINI_FLASH_MODEL,
  },
  extract_temporal_echoes: {
    role: 'extractor',
    provider: 'gemini',
    model: gemini.GEMINI_FLASH_MODEL,
  },
  extract_entities: {
    role: 'extractor',
    provider: 'gemini',
    model: gemini.GEMINI_FLASH_MODEL,
  },
  // Synthesizer — long-context summarization
  generate_summary: {
    role: 'synthesizer',
    provider: 'gemini',
    model: gemini.GEMINI_PRO_MODEL,
  },
};

/**
 * Get the route config for a given action.
 */
export function getRoute(action: string): RouteConfig {
  const route = ROUTE_MAP[action];
  if (!route) {
    // Default: fall back to conversationalist (Haiku)
    return {
      role: 'conversationalist',
      provider: 'anthropic',
      model: 'claude-haiku-4-5-20251001',
    };
  }
  return route;
}

/**
 * Send a text-only message through the router.
 * Works for both Anthropic and Gemini providers.
 */
export async function sendMessage(
  action: string,
  messages: { role: 'user' | 'assistant'; content: string }[],
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
  } = {}
): Promise<RoutedResponse> {
  const route = getRoute(action);

  if (route.provider === 'anthropic') {
    const response = await anthropic.sendMessage(messages, {
      ...options,
      model: route.model,
    });
    return {
      content: response.content,
      provider: 'anthropic',
      model: response.model,
      usage: response.usage,
    };
  }

  // Gemini
  const response = await gemini.sendMessage(messages, {
    ...options,
    model: route.model,
  });
  return {
    content: response.content,
    provider: 'gemini',
    model: response.model,
    usage: response.usage,
  };
}

/**
 * Send a message with tools (Architect role only — always Claude).
 * Tool calling stays on Claude because it has the best tool-use accuracy.
 */
export async function sendWithTools(
  messages: { role: 'user' | 'assistant'; content: string }[],
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
    tools?: unknown[];
  } = {}
): Promise<RoutedRawResponse> {
  const route = getRoute('send_with_tools');

  const response = await anthropic.sendRaw(messages, {
    ...options,
    model: route.model,
  });

  return {
    content: response.content,
    provider: 'anthropic',
    model: response.model,
    usage: response.usage,
    stop_reason: response.stop_reason,
  };
}

/**
 * Log usage with provider information.
 */
export async function logRoutedUsage(params: {
  supabase: SupabaseClient;
  userId: string;
  action: string;
  provider: AIProvider;
  model: string;
  inputTokens: number;
  outputTokens: number;
}): Promise<void> {
  try {
    const { error } = await params.supabase.from('usage_log').insert({
      user_id: params.userId,
      action: params.action,
      input_tokens: params.inputTokens,
      output_tokens: params.outputTokens,
      model: params.model,
      provider: params.provider,
    });
    if (error) {
      console.error('logRoutedUsage insert error:', error.message);
    }
  } catch (err) {
    console.error('logRoutedUsage error:', err);
  }
}
