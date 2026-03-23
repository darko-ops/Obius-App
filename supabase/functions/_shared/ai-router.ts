// AI Router — maps each action to the cheapest capable provider.
//
// Cost comparison (per 1M tokens, approximate):
//   Claude Haiku 4.5:  $0.80 input / $4.00 output
//   Gemini 2.0 Flash:  $0.10 input / $0.40 output  (~8x cheaper)
//   Claude Sonnet 4:   $3.00 input / $15.00 output  (premium)
//
// Strategy:
//   • Simple extraction (titles, tags, JSON) → Gemini Flash (cheapest)
//   • Conversational + tool use            → Claude Haiku (best tool support)
//   • Fallback: if Gemini is unavailable, all routes go to Claude Haiku.

import { sendGeminiMessage } from './gemini-client.ts';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY')!;
const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') || '';
const CLAUDE_FALLBACK_MODEL = 'claude-haiku-4-5-20251001';

export type AIProvider = 'claude' | 'gemini';

export interface RoutedResponse {
  content: string;
  model: string;
  provider: AIProvider;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
}

// Which actions can be handled by the cheap provider (Gemini Flash)
const CHEAP_ACTIONS = new Set([
  'generate_title',
  'generate_tags',
  'extract_temporal_echoes',
  'extract_entities',
  'generate_summary',
  'refine_title',
]);

// Actions that require Claude (tool use, complex conversation)
const CLAUDE_ACTIONS = new Set([
  'send_with_tools',
  'send_chat',
]);

/**
 * Determine which provider to use for a given action.
 */
export function resolveProvider(action: string): AIProvider {
  if (!GEMINI_API_KEY) {
    return 'claude';
  }
  if (CHEAP_ACTIONS.has(action)) {
    return 'gemini';
  }
  return 'claude';
}

/**
 * Direct Claude call (avoids circular import with anthropic-client.ts).
 */
async function sendClaudeDirect(
  userMessage: string,
  options: { maxTokens?: number; temperature?: number; system?: string; model?: string }
): Promise<RoutedResponse> {
  const { maxTokens = 1024, temperature = 0.7, system, model } = options;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: model || CLAUDE_FALLBACK_MODEL,
      max_tokens: maxTokens,
      temperature,
      system,
      messages: [{ role: 'user', content: userMessage }],
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Anthropic API error: ${error.error?.message || response.statusText}`);
  }

  const data = await response.json();
  return {
    content: data.content[0].text,
    model: data.model,
    provider: 'claude',
    usage: data.usage,
  };
}

/**
 * Send a simple text completion through the optimal provider for the action.
 * For simple extraction tasks, this routes to Gemini Flash.
 * For complex tasks or when Gemini is unavailable, it routes to Claude.
 */
export async function routedSendMessage(
  action: string,
  userMessage: string,
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
    claudeModel?: string;
  } = {}
): Promise<RoutedResponse> {
  const provider = resolveProvider(action);

  if (provider === 'gemini') {
    try {
      const response = await sendGeminiMessage(userMessage, {
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        system: options.system,
      });
      return {
        content: response.content,
        model: response.model,
        provider: 'gemini',
        usage: response.usage,
      };
    } catch (error) {
      // Fallback to Claude if Gemini fails
      console.warn(`Gemini failed for ${action}, falling back to Claude:`, error.message);
    }
  }

  // Claude path (primary for complex tasks, fallback for simple ones)
  return sendClaudeDirect(userMessage, {
    maxTokens: options.maxTokens,
    temperature: options.temperature,
    system: options.system,
    model: options.claudeModel,
  });
}

export { CHEAP_ACTIONS, CLAUDE_ACTIONS };
