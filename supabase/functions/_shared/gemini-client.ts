// Google Gemini Client for Edge Functions

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const GOOGLE_AI_API_KEY = Deno.env.get('GOOGLE_AI_API_KEY')!;
const GEMINI_MODEL = 'gemini-2.0-flash';

export interface GeminiMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface GeminiResponse {
  content: string;
  model: string;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
  stop_reason: string;
}

/**
 * Strip markdown code fences that Gemini sometimes wraps around JSON output.
 */
function stripCodeFences(text: string): string {
  const fenced = text.match(/^```(?:json)?\s*\n?([\s\S]*?)\n?\s*```$/);
  return fenced ? fenced[1].trim() : text;
}

/**
 * Send a message to Gemini and get a text response.
 * Returns the same shape as ClaudeResponse for drop-in compatibility.
 */
export async function sendGeminiMessage(
  messages: GeminiMessage[],
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
    model?: string;
  } = {}
): Promise<GeminiResponse> {
  if (!GOOGLE_AI_API_KEY) {
    throw new Error('GOOGLE_AI_API_KEY not configured');
  }

  const { maxTokens = 1024, temperature = 0.7, system, model } = options;
  const modelId = model || GEMINI_MODEL;

  // Translate Anthropic-style messages to Gemini contents format.
  // Gemini uses "model" instead of "assistant" for the AI role.
  const contents = messages.map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

  const payload: Record<string, unknown> = {
    contents,
    generationConfig: {
      maxOutputTokens: maxTokens,
      temperature,
    },
  };

  // Gemini supports systemInstruction as a top-level field
  if (system) {
    payload.systemInstruction = { parts: [{ text: system }] };
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=${GOOGLE_AI_API_KEY}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(
      `Gemini API error: ${error.error?.message || response.statusText}`
    );
  }

  const data = await response.json();

  const candidate = data.candidates?.[0];
  if (!candidate || !candidate.content?.parts?.length) {
    throw new Error('Gemini returned no content');
  }

  const text = candidate.content.parts
    .map((p: { text?: string }) => p.text || '')
    .join('');

  const usage = data.usageMetadata || {};

  return {
    content: stripCodeFences(text.trim()),
    model: modelId,
    usage: {
      input_tokens: usage.promptTokenCount || 0,
      output_tokens: usage.candidatesTokenCount || 0,
    },
    stop_reason: (candidate.finishReason || 'STOP').toLowerCase(),
  };
}

/**
 * Generate a note title and summary using Gemini.
 * Drop-in replacement for generateNoteSummary() in anthropic-client.
 */
export async function generateNoteSummaryGemini(
  content: string
): Promise<{ title: string; summary: string }> {
  const response = await sendGeminiMessage(
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
      system:
        'You are a helpful assistant that generates concise titles and summaries for notes. Always respond with valid JSON only, no other text.',
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
    const lines = content.split('\n').filter((l) => l.trim());
    return {
      title: lines[0]?.slice(0, 50) || 'Untitled',
      summary: lines.slice(0, 3).join(' ').slice(0, 200) || '',
    };
  }
}

export { GEMINI_MODEL };
