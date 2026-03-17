// OBIUS AI Proxy Edge Function
// Routes all AI operations through a single endpoint, keeping the API key server-side.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  verifyAuth,
  createServiceClient,
  jsonResponse,
  errorResponse,
  corsResponse,
} from '../_shared/supabase-client.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { sendMessage, sendRaw, logUsage } from '../_shared/anthropic-client.ts';

const AI_MODEL = 'claude-haiku-4-5-20251001';

// ---------- Prompt loader ----------

// Read prompt templates from _shared/prompts/ at import time.
// Deno Deploy bundles these files so they're available at runtime.
async function loadPrompt(name: string): Promise<string> {
  try {
    return await Deno.readTextFile(
      new URL(`../_shared/prompts/${name}.md`, import.meta.url)
    );
  } catch {
    console.warn(`Prompt file ${name}.md not found, using fallback`);
    return '';
  }
}

// Cache prompts on first request
let promptCache: Record<string, string> = {};
async function getPrompt(name: string): Promise<string> {
  if (!promptCache[name]) {
    promptCache[name] = await loadPrompt(name);
  }
  return promptCache[name];
}

// ---------- Tool definitions for send_with_tools ----------

const TOOL_DEFINITIONS = [
  {
    name: 'schedule_echo',
    description:
      'Schedule an Echo (reminder/alert) on a loop. The user will see a confirmation card before it executes.',
    input_schema: {
      type: 'object',
      properties: {
        handle_id: { type: 'string', description: 'The UUID of the handle to attach the echo to' },
        handle_name: { type: 'string', description: 'The display name of the handle (for the confirmation card)' },
        is_recurring: { type: 'boolean', description: 'Whether the echo repeats on an interval' },
        interval_value: { type: 'integer', description: "Numeric interval value (e.g. 3 for 'every 3 days')" },
        interval_unit: {
          type: 'string',
          enum: ['minutes', 'hours', 'days', 'weeks', 'months'],
          description: 'Interval time unit',
        },
        fire_date: { type: 'string', description: 'ISO-8601 date-time for the first fire' },
      },
      required: ['handle_id', 'handle_name', 'is_recurring', 'interval_value', 'interval_unit', 'fire_date'],
    },
  },
  {
    name: 'set_note_intent',
    description:
      'Set the intent/category of a note. The user will see a confirmation card before it executes.',
    input_schema: {
      type: 'object',
      properties: {
        note_id: { type: 'string', description: 'The UUID of the note' },
        note_title: { type: 'string', description: 'The title of the note (for the confirmation card)' },
        intent: {
          type: 'string',
          enum: ['idea', 'question', 'task', 'evidence'],
          description: 'The intent to set',
        },
      },
      required: ['note_id', 'note_title', 'intent'],
    },
  },
  {
    name: 'promote_to_handle',
    description:
      'Promote a section (node) to a loop. The user will see a confirmation card before it executes.',
    input_schema: {
      type: 'object',
      properties: {
        section_id: { type: 'string', description: 'The UUID of the section to promote' },
        section_preview: { type: 'string', description: 'Short preview of the section content' },
        handle_name: { type: 'string', description: 'Name for the new loop (2-50 chars, letters/numbers/underscores)' },
      },
      required: ['section_id', 'section_preview', 'handle_name'],
    },
  },
  {
    name: 'update_loop_content',
    description:
      'Suggest updated content for a loop. Use this when the user asks you to refine, rewrite, expand, or edit a loop\'s content. The user will see the proposed changes and can accept or dismiss.',
    input_schema: {
      type: 'object',
      properties: {
        handle_id: { type: 'string', description: 'The UUID of the loop to update' },
        handle_name: { type: 'string', description: 'The display name of the loop (for the confirmation card)' },
        new_content: { type: 'string', description: 'The full updated content for the loop' },
      },
      required: ['handle_id', 'handle_name', 'new_content'],
    },
  },
  {
    name: 'update_page_body',
    description:
      'Suggest updated body text for a page. Use this when the user asks you to refine, rewrite, expand, or edit a page\'s body text (not sections). The user will see the proposed changes and can accept or dismiss.',
    input_schema: {
      type: 'object',
      properties: {
        note_id: { type: 'string', description: 'The UUID of the page to update' },
        note_title: { type: 'string', description: 'The title of the page (for the confirmation card)' },
        new_body: { type: 'string', description: 'The full updated body text for the page' },
      },
      required: ['note_id', 'note_title', 'new_body'],
    },
  },
  {
    name: 'delete_section',
    description:
      'Delete a section (node or line) from the focused page. If the user says "remove the node" and there are multiple nodes, ask which one first.',
    input_schema: {
      type: 'object',
      properties: {
        section_id: { type: 'string', description: 'The UUID of the section to delete' },
        section_preview: { type: 'string', description: 'Short preview of the section content (for the confirmation card)' },
      },
      required: ['section_id', 'section_preview'],
    },
  },
  {
    name: 'update_section_content',
    description:
      'Update the content of a specific section by ID. More precise than update_page_body — use this when the user wants to edit a particular node or line.',
    input_schema: {
      type: 'object',
      properties: {
        section_id: { type: 'string', description: 'The UUID of the section to update' },
        section_preview: { type: 'string', description: 'Short preview of current content (for the confirmation card)' },
        new_content: { type: 'string', description: 'The full updated content for this section' },
      },
      required: ['section_id', 'section_preview', 'new_content'],
    },
  },
  {
    name: 'create_section',
    description:
      'Create a new section (node or line) on the focused page. Use this when the user asks to add a node, create a section, convert content into a node, turn text into nodes, or restructure a page into sections. Call this tool MULTIPLE TIMES to create several nodes at once.',
    input_schema: {
      type: 'object',
      properties: {
        note_id: { type: 'string', description: 'The UUID of the page to add the section to' },
        note_title: { type: 'string', description: 'The title of the page (for the confirmation card)' },
        content: { type: 'string', description: 'The content for the new section' },
        section_type: {
          type: 'string',
          enum: ['fold', 'line'],
          description: 'fold = node with colored background, line = plain text',
        },
        content_type: {
          type: 'string',
          enum: ['text', 'checklist', 'code', 'quote'],
          description: 'The content type (default: text)',
        },
        after_section_id: {
          type: 'string',
          description: 'Insert after this section ID. Null or omitted = add at the end.',
        },
        intent: {
          type: 'string',
          enum: ['idea', 'question', 'task', 'evidence'],
          description: 'The intent/color for the new section (default: idea)',
        },
      },
      required: ['note_id', 'content', 'section_type'],
    },
  },
  {
    name: 'move_section',
    description:
      'Move a section to a new position within the page. Specify which section to place it after.',
    input_schema: {
      type: 'object',
      properties: {
        section_id: { type: 'string', description: 'The UUID of the section to move' },
        section_preview: { type: 'string', description: 'Short preview of the section content' },
        after_section_id: {
          type: 'string',
          description: 'Place after this section ID. Null or omitted = move to the top.',
        },
      },
      required: ['section_id', 'section_preview'],
    },
  },
  {
    name: 'set_section_intent',
    description:
      'Change the intent/color of a specific section.',
    input_schema: {
      type: 'object',
      properties: {
        section_id: { type: 'string', description: 'The UUID of the section' },
        section_preview: { type: 'string', description: 'Short preview of the section content' },
        intent: {
          type: 'string',
          enum: ['idea', 'question', 'task', 'evidence'],
          description: 'The new intent to set',
        },
      },
      required: ['section_id', 'section_preview', 'intent'],
    },
  },
];

// ---------- System prompt builders ----------

async function systemPromptForSendWithTools(noteContext: string): Promise<string> {
  const template = await getPrompt('send_with_tools');
  if (template) {
    return template.replace('{{NOTE_CONTEXT}}', noteContext);
  }
  // Fallback if prompt file not found
  return `You are the intelligence assistant inside Obius, a note-taking app. Help users organize and edit notes. Be concise.\n\nContext:\n${noteContext}`;
}

async function systemPromptForChat(noteContext: string): Promise<string> {
  const template = await getPrompt('send_chat');
  if (template) {
    return template.replace('{{NOTE_CONTEXT}}', noteContext);
  }
  return `You are the intelligence assistant inside Obius. Help the user discuss their content conversationally.\n\nContext:\n${noteContext}`;
}

async function getGenerateTitleSystem(): Promise<string> {
  return (await getPrompt('generate_title')) ||
    'You are a title generator. Given note content, respond with ONLY a short title (2-5 words). No quotes, no punctuation, no explanation.';
}

async function getGenerateTagsSystem(): Promise<string> {
  return (await getPrompt('generate_tags')) ||
    'You are a keyword tagger. Respond with ONLY a comma-separated list of 1-4 single-word tags.';
}

async function systemPromptForTemporalEchoes(todayISO: string): Promise<string> {
  const template = await getPrompt('temporal_echoes');
  if (template) {
    return template.replace('{{TODAY_ISO}}', todayISO);
  }
  return `You are a temporal phrase detector. Today is ${todayISO}. Return a JSON array of echo suggestions.`;
}

async function getExtractEntitiesSystem(): Promise<string> {
  return (await getPrompt('extract_entities')) ||
    'Analyze note sections for recurring entities. Return a JSON array.';
}

// ---------- Action handlers ----------

interface ActionRequest {
  action: string;
  [key: string]: unknown;
}

async function handleSendWithTools(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const messages = body.messages as { role: string; content: string }[];
  const noteContext = (body.noteContext as string) || '';

  if (!messages || !Array.isArray(messages)) {
    return errorResponse('INVALID_REQUEST', 'messages array is required');
  }

  const system = await systemPromptForSendWithTools(noteContext);

  const raw = await sendRaw(
    messages.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content })),
    {
      model: AI_MODEL,
      maxTokens: 4096,
      system,
      tools: TOOL_DEFINITIONS,
    }
  );

  logUsage({ supabase, userId, action: 'chat', inputTokens: raw.usage.input_tokens, outputTokens: raw.usage.output_tokens, model: raw.model }).catch(() => {});

  return jsonResponse({ content: raw.content });
}

async function handleSendChat(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const messages = body.messages as { role: string; content: string }[];
  const noteContext = (body.noteContext as string) || '';

  if (!messages || !Array.isArray(messages)) {
    return errorResponse('INVALID_REQUEST', 'messages array is required');
  }

  const system = await systemPromptForChat(noteContext);

  const response = await sendMessage(
    messages.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content })),
    {
      maxTokens: 4096,
      system,
      model: AI_MODEL,
    }
  );

  logUsage({ supabase, userId, action: 'chat_convo', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

async function handleGenerateTitle(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const content = body.content as string;
  if (!content) {
    return errorResponse('INVALID_REQUEST', 'content is required');
  }

  const system = await getGenerateTitleSystem();
  const response = await sendMessage(
    [{ role: 'user', content: `Generate a short title for this note:\n\n${content}` }],
    { maxTokens: 30, system, model: AI_MODEL }
  );

  logUsage({ supabase, userId, action: 'title_gen', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

async function handleGenerateTags(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const content = body.content as string;
  if (!content) {
    return errorResponse('INVALID_REQUEST', 'content is required');
  }

  const system = await getGenerateTagsSystem();
  const response = await sendMessage(
    [{ role: 'user', content: `Extract keyword tags from this note:\n\n${content}` }],
    { maxTokens: 50, system, model: AI_MODEL }
  );

  logUsage({ supabase, userId, action: 'tag_gen', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

async function handleExtractTemporalEchoes(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const noteSummaries = body.noteSummaries as string;
  const handles = body.handles as string;

  if (!noteSummaries) {
    return errorResponse('INVALID_REQUEST', 'noteSummaries is required');
  }

  const todayISO = new Date().toISOString();
  const system = await systemPromptForTemporalEchoes(todayISO);
  const response = await sendMessage(
    [{ role: 'user', content: `Notes:\n${noteSummaries}\n\nHandles:\n${handles || ''}` }],
    { maxTokens: 512, system, model: AI_MODEL }
  );

  logUsage({ supabase, userId, action: 'temporal_echo', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

async function handleExtractEntities(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const sectionsText = body.sectionsText as string;
  if (!sectionsText) {
    return errorResponse('INVALID_REQUEST', 'sectionsText is required');
  }

  const system = await getExtractEntitiesSystem();
  const response = await sendMessage(
    [{ role: 'user', content: sectionsText }],
    { maxTokens: 256, system, model: AI_MODEL }
  );

  logUsage({ supabase, userId, action: 'entity_extract', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

// ---------- Router ----------

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    // Auth is optional — AI works for both signed-in and local-only users
    let userId = 'anonymous';
    try {
      const auth = await verifyAuth(req);
      userId = auth.userId;
    } catch {
      // No valid session — continue as anonymous
    }
    const supabase = createServiceClient();

    const body: ActionRequest = await req.json();
    const { action } = body;

    switch (action) {
      case 'send_with_tools':
        return await handleSendWithTools(body, userId, supabase);
      case 'send_chat':
        return await handleSendChat(body, userId, supabase);
      case 'generate_title':
        return await handleGenerateTitle(body, userId, supabase);
      case 'generate_tags':
        return await handleGenerateTags(body, userId, supabase);
      case 'extract_temporal_echoes':
        return await handleExtractTemporalEchoes(body, userId, supabase);
      case 'extract_entities':
        return await handleExtractEntities(body, userId, supabase);
      default:
        return errorResponse('UNKNOWN_ACTION', `Unknown action: ${action}`);
    }
  } catch (error) {
    console.error('ai-proxy error:', error);
    return errorResponse('INTERNAL_ERROR', error.message || 'An unexpected error occurred', 500);
  }
});
