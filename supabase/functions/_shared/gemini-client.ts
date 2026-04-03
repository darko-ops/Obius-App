// Google Gemini Client for Edge Functions
// Handles Flash (extraction) and Pro (synthesis) model calls.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')!;

export const GEMINI_FLASH_MODEL = 'gemini-2.0-flash';
export const GEMINI_PRO_MODEL = 'gemini-2.0-pro';

export interface GeminiMessage {
  role: 'user' | 'model';
  parts: { text: string }[];
}

export interface GeminiResponse {
  content: string;
  model: string;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
  finish_reason: string;
}

/**
 * Convert Claude-style messages to Gemini format.
 * Claude uses role "assistant", Gemini uses "model".
 */
function toGeminiMessages(
  messages: { role: 'user' | 'assistant'; content: string }[]
): GeminiMessage[] {
  return messages.map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));
}

/**
 * Send a message to Gemini and get a text response.
 */
export async function sendMessage(
  messages: { role: 'user' | 'assistant'; content: string }[],
  options: {
    model?: string;
    maxTokens?: number;
    temperature?: number;
    system?: string;
  } = {}
): Promise<GeminiResponse> {
  if (!GEMINI_API_KEY) {
    throw new Error('GEMINI_API_KEY not configured');
  }

  const {
    model = GEMINI_FLASH_MODEL,
    maxTokens = 1024,
    temperature = 0.7,
    system,
  } = options;

  const geminiMessages = toGeminiMessages(messages);

  const payload: Record<string, unknown> = {
    contents: geminiMessages,
    generationConfig: {
      maxOutputTokens: maxTokens,
      temperature,
    },
  };

  // Gemini uses systemInstruction for system prompts
  if (system) {
    payload.systemInstruction = {
      parts: [{ text: system }],
    };
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const error = await response.json();
    const message =
      error.error?.message || response.statusText || 'Unknown Gemini API error';
    throw new Error(`Gemini API error: ${message}`);
  }

  const data = await response.json();

  const candidate = data.candidates?.[0];
  if (!candidate) {
    throw new Error('Gemini API returned no candidates');
  }

  const text =
    candidate.content?.parts
      ?.map((p: { text?: string }) => p.text || '')
      .join('') || '';

  const usageMetadata = data.usageMetadata || {};

  return {
    content: text,
    model,
    usage: {
      input_tokens: usageMetadata.promptTokenCount || 0,
      output_tokens: usageMetadata.candidatesTokenCount || 0,
    },
    finish_reason: candidate.finishReason || 'STOP',
  };
}

/**
 * Generate a note summary using Gemini Pro (optimized for long-context synthesis).
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
${content.slice(0, 30000)}

Respond ONLY with valid JSON in this exact format:
{"title": "Your title here", "summary": "Your summary here"}`,
      },
    ],
    {
      model: GEMINI_PRO_MODEL,
      maxTokens: 200,
      temperature: 0.3,
      system:
        'You are a helpful assistant that generates concise titles and summaries for notes. Always respond with valid JSON only, no other text.',
    }
  );

  try {
    // Strip markdown code fences if present
    let jsonStr = response.content.trim();
    if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
    }
    const result = JSON.parse(jsonStr);
    return {
      title: result.title?.slice(0, 50) || 'Untitled',
      summary: result.summary?.slice(0, 200) || '',
    };
  } catch {
    const lines = content.split('\n').filter((l) => l.trim());
    return {
      title: lines[0]?.slice(0, 50) || 'Untitled',
      summary: lines.slice(0, 3).join(' ').slice(0, 200) || '',
    };
  }
}

/**
 * Refine/improve a user-provided title using Gemini Pro.
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
      model: GEMINI_PRO_MODEL,
      maxTokens: 60,
      temperature: 0.3,
      system:
        'You refine note titles. Respond with only the title text, nothing else.',
    }
  );

  return response.content.trim().slice(0, 50) || currentTitle;
}
