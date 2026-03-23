// Google Gemini Client for Edge Functions
// Used for simple extraction tasks (titles, tags, summaries, JSON extraction)
// at a fraction of the cost of Claude.

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') || '';
const GEMINI_MODEL = 'gemini-2.0-flash';

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
}

/**
 * Send a message to Gemini and get a text response.
 */
export async function sendGeminiMessage(
  userMessage: string,
  options: {
    maxTokens?: number;
    temperature?: number;
    system?: string;
    model?: string;
  } = {}
): Promise<GeminiResponse> {
  if (!GEMINI_API_KEY) {
    throw new Error('GEMINI_API_KEY not configured');
  }

  const { maxTokens = 1024, temperature = 0.7, system, model } = options;
  const useModel = model || GEMINI_MODEL;

  const contents: GeminiMessage[] = [
    { role: 'user', parts: [{ text: userMessage }] },
  ];

  const payload: Record<string, unknown> = {
    contents,
    generationConfig: {
      maxOutputTokens: maxTokens,
      temperature,
    },
  };

  if (system) {
    payload.systemInstruction = { parts: [{ text: system }] };
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${useModel}:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(
      `Gemini API error: ${error.error?.message || response.statusText}`
    );
  }

  const data = await response.json();

  const text =
    data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  const usageMetadata = data.usageMetadata || {};

  return {
    content: text,
    model: useModel,
    usage: {
      input_tokens: usageMetadata.promptTokenCount || 0,
      output_tokens: usageMetadata.candidatesTokenCount || 0,
    },
  };
}

export { GEMINI_MODEL };
