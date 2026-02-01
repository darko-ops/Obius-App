// OpenAI Client for Edge Functions

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!;
const EMBEDDING_MODEL = 'text-embedding-3-small';
const EMBEDDING_DIMENSIONS = 1536;

export interface EmbeddingResult {
  embedding: number[];
  model: string;
  usage: {
    prompt_tokens: number;
    total_tokens: number;
  };
}

/**
 * Generate embedding for text using OpenAI
 */
export async function generateEmbedding(text: string): Promise<EmbeddingResult> {
  if (!OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY not configured');
  }

  // Truncate text if too long (max ~8000 tokens for embedding model)
  const truncatedText = text.slice(0, 30000);

  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input: truncatedText,
      dimensions: EMBEDDING_DIMENSIONS,
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`OpenAI API error: ${error.error?.message || response.statusText}`);
  }

  const data = await response.json();

  return {
    embedding: data.data[0].embedding,
    model: EMBEDDING_MODEL,
    usage: data.usage,
  };
}

/**
 * Generate embeddings for multiple texts (batched)
 */
export async function generateEmbeddings(texts: string[]): Promise<EmbeddingResult[]> {
  if (!OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY not configured');
  }

  if (texts.length === 0) {
    return [];
  }

  // Truncate each text
  const truncatedTexts = texts.map(t => t.slice(0, 30000));

  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input: truncatedTexts,
      dimensions: EMBEDDING_DIMENSIONS,
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`OpenAI API error: ${error.error?.message || response.statusText}`);
  }

  const data = await response.json();

  return data.data.map((item: { embedding: number[] }, index: number) => ({
    embedding: item.embedding,
    model: EMBEDDING_MODEL,
    usage: index === 0 ? data.usage : { prompt_tokens: 0, total_tokens: 0 },
  }));
}

export { EMBEDDING_MODEL, EMBEDDING_DIMENSIONS };
