// Anthropic Claude Client for Edge Functions

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY')!;
const CLAUDE_MODEL = 'claude-sonnet-4-20250514'; // Architect default — used for tool calling & reasoning

export interface ClaudeMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface ClaudeUsage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}

export interface ClaudeResponse {
  content: string;
  model: string;
  usage: ClaudeUsage;
  stop_reason: string;
}

export interface ClaudeRawResponse {
  content: unknown[];
  model: string;
  usage: ClaudeUsage;
  stop_reason: string;
}

/**
 * Send a message to Claude and get a response (text only).
 */
export async function sendMessage(
  messages: ClaudeMessage[],
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
    model?: string;
  } = {}
): Promise<ClaudeResponse> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error('ANTHROPIC_API_KEY not configured');
  }

  const { maxTokens = 1024, temperature = 0.7, system, model } = options;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: model || CLAUDE_MODEL,
      max_tokens: maxTokens,
      temperature,
      system,
      messages,
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
    usage: data.usage,
    stop_reason: data.stop_reason,
  };
}

/**
 * Send a message to Claude and return the full raw response (including tool_use blocks).
 */
export async function sendRaw(
  messages: ClaudeMessage[],
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
    model?: string;
    tools?: unknown[];
  } = {}
): Promise<ClaudeRawResponse> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error('ANTHROPIC_API_KEY not configured');
  }

  const { maxTokens = 1024, temperature = 0.7, system, model, tools } = options;

  const payload: Record<string, unknown> = {
    model: model || CLAUDE_MODEL,
    max_tokens: maxTokens,
    temperature,
    system,
    messages,
  };

  if (tools && tools.length > 0) {
    payload.tools = tools;
  }

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Anthropic API error: ${error.error?.message || response.statusText}`);
  }

  const data = await response.json();

  return {
    content: data.content,
    model: data.model,
    usage: data.usage,
    stop_reason: data.stop_reason,
  };
}

/**
 * Generate a note title and summary from content
 */
export async function generateNoteSummary(
  content: string
): Promise<{ title: string; summary: string }> {
  const response = await sendMessage(
    [
      {
        role: 'user',
        content: `Based on this note content, generate:
1. A concise title (max 50 characters, no quotes)
2. A brief summary (max 200 characters)

Content:
${content.slice(0, 10000)}

Respond ONLY with valid JSON in this exact format:
{"title": "Your title here", "summary": "Your summary here"}`,
      },
    ],
    {
      maxTokens: 200,
      temperature: 0.3,
      system: 'You are a helpful assistant that generates concise titles and summaries for notes. Always respond with valid JSON only, no other text.',
    }
  );

  try {
    const result = JSON.parse(response.content);
    return {
      title: result.title?.slice(0, 50) || 'Untitled',
      summary: result.summary?.slice(0, 200) || '',
    };
  } catch {
    // Fallback if JSON parsing fails
    const lines = content.split('\n').filter(l => l.trim());
    return {
      title: lines[0]?.slice(0, 50) || 'Untitled',
      summary: lines.slice(0, 3).join(' ').slice(0, 200) || '',
    };
  }
}

/**
 * Refine/improve a user-provided title
 */
export async function refineTitle(
  currentTitle: string,
  content: string
): Promise<string> {
  const response = await sendMessage(
    [
      {
        role: 'user',
        content: `Current title: "${currentTitle}"

Note content:
${content.slice(0, 5000)}

Suggest a slightly improved or refined version of this title. Keep it concise (max 50 chars) and preserve the user's intent. If the current title is already good, return it unchanged.

Respond with ONLY the title, no quotes or explanation.`,
      },
    ],
    {
      maxTokens: 60,
      temperature: 0.3,
      system: 'You refine note titles. Respond with only the title text, nothing else.',
    }
  );

  return response.content.trim().slice(0, 50) || currentTitle;
}

/**
 * Log token usage to the usage_log table. Fire-and-forget — errors are logged but never thrown.
 */
export async function logUsage(params: {
  supabase: SupabaseClient;
  userId: string;
  action: string;
  inputTokens: number;
  outputTokens: number;
  model: string;
  cacheCreationInputTokens?: number;
  cacheReadInputTokens?: number;
}): Promise<void> {
  try {
    const { error } = await params.supabase.from('usage_log').insert({
      user_id: params.userId,
      action: params.action,
      input_tokens: params.inputTokens,
      output_tokens: params.outputTokens,
      model: params.model,
      cache_creation_input_tokens: params.cacheCreationInputTokens ?? 0,
      cache_read_input_tokens: params.cacheReadInputTokens ?? 0,
    });
    if (error) {
      console.error('logUsage insert error:', error.message);
    }
  } catch (err) {
    console.error('logUsage error:', err);
  }
}

export { CLAUDE_MODEL };
