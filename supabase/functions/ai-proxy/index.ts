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
import { routedSendMessage, resolveProvider } from '../_shared/ai-router.ts';

const AI_MODEL = 'claude-haiku-4-5-20251001';

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
      'Suggest updated body text for a page. Use this when the user asks you to refine, rewrite, expand, or edit a page\'s content. The user will see the proposed changes and can accept or dismiss.',
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
      'Delete a section (node or line) from the focused page. The user will see a confirmation card before it executes. If the user says "remove the node" and there are multiple nodes, ask them which one they mean before calling this tool.',
    input_schema: {
      type: 'object',
      properties: {
        section_id: { type: 'string', description: 'The UUID of the section to delete' },
        section_preview: { type: 'string', description: 'Short preview of the section content (for the confirmation card)' },
      },
      required: ['section_id', 'section_preview'],
    },
  },
];

// ---------- System prompts per action ----------

function systemPromptForSendWithTools(noteContext: string): string {
  return `You are the intelligence assistant inside Obius, a note-taking app. \
Answer questions about the user's notes and help them stay organised. \
Be concise and helpful.

You can suggest actions using your tools. The user will see each action \
as a card with Accept/Dismiss buttons — the action only executes if \
accepted. Suggest actions when clearly relevant. You may combine text \
with tool calls.

When the user asks you to edit, refine, rewrite, or improve a page's body, \
use the update_page_body tool to propose the new content.

When the user asks you to edit, refine, rewrite, or improve a loop's content, \
use the update_loop_content tool to propose the new content.

When the user asks to delete or remove a node/section, check the sections list in the context. \
If there is exactly one node (type: node), use the delete_section tool with that section's ID. \
If there are multiple nodes and the user's request is ambiguous (e.g. "remove the node"), \
ask them which one they mean by listing the nodes with their content previews. \
If the user specifies enough detail to identify which node, use delete_section directly.

The user's workspace shows the focused content above and your suggestion as an \
action card they can accept. Use the correct tool for the focused item (page vs loop).

Available intents: idea (blue), question (yellow), task (green), evidence (purple).
Loop names: 2-50 chars, letters/numbers/underscores only.

Current workspace context:
${noteContext}`;
}

const GENERATE_TITLE_SYSTEM =
  'You are a title generator. Given note content, respond with ONLY a short title (2-5 words). No quotes, no punctuation, no explanation.';

const GENERATE_TAGS_SYSTEM =
  'You are a keyword tagger. Given note content, extract the most important specific keywords — concrete nouns, names, tools, or topics actually mentioned in the text. Prefer specific words from the content over abstract concepts. Respond with ONLY a comma-separated list of 1-4 single-word tags. No hashtags, no quotes, no explanation. Example: swift, authentication, firebase';

function systemPromptForTemporalEchoes(todayISO: string): string {
  return `You are a temporal phrase detector for Obius, a note-taking app with Echoes (reminders). \
Analyze the notes and identify temporal phrases that imply the user should be reminded \
about something. Examples: "follow up Thursday", "revisit in 2 weeks", "check back next month", \
"dentist appointment at 3pm", "deadline Friday", "every Monday".

You also receive a list of existing handles (loops). If a temporal phrase relates to a specific \
existing handle, use that handle's ID and displayName. Otherwise, set handleId to "new" and \
set handleName to a short, descriptive snake_case name derived from the context \
(e.g. "dentist_appointment", "client_followup", "weekly_standup"). \
NEVER use "none" as a handleName — always derive a meaningful name from the content.

Return a JSON array of objects with: \
"handleId" (UUID of an existing handle, or "new" if suggesting a new handle), \
"handleName" (display name — MUST be descriptive, e.g. "dentist_appointment" not "none"), \
"phrase" (the exact temporal phrase found in the note), \
"isRecurring" (boolean), \
"intervalValue" (integer, e.g. 1 for "every week"), \
"intervalUnit" (one of: minutes, hours, days, weeks, months), \
"fireDateISO" (ISO-8601 date-time for when the echo should first fire), \
"noteId" (the note's ID where the phrase was found).

For non-recurring echoes, set intervalValue=0 and intervalUnit="days". \
For recurring, set the appropriate interval. \
Use today's date context to compute fireDateISO from relative phrases like "Thursday" or "next week". \
Today is ${todayISO}. \
Max 3 suggestions. Return [] if nothing qualifies. \
Return ONLY the JSON array, no other text.`;
}

function systemPromptForChat(noteContext: string): string {
  return `You are the intelligence assistant inside Obius, a note-taking app. \
The user wants to discuss and analyze their content conversationally. \
Answer questions, give opinions, summarize, compare, and help them think. \
Do NOT suggest edits, changes, or tool-based actions — just have a helpful conversation.

Current workspace context:
${noteContext}`;
}

const EXTRACT_ENTITIES_SYSTEM = `Analyze the following note sections and identify recurring entities (people, places, projects, \
topics, lists) that the user references repeatedly or that would benefit from being a synced \
Loop (a content block that stays consistent across pages).

Return a JSON array of objects with: "name" (display name), "handleName" (lowercase, \
underscores, 2-50 chars), "reason" (1 sentence why), "sectionId" (which section contains it).

Only suggest entities that genuinely recur or would benefit from syncing. Max 3 suggestions. \
Return [] if nothing qualifies. Return ONLY the JSON array, no other text.`;

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

  const raw = await sendRaw(
    messages.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content })),
    {
      model: AI_MODEL,
      maxTokens: 1024,
      system: systemPromptForSendWithTools(noteContext),
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

  const response = await sendMessage(
    messages.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content })),
    {
      maxTokens: 1024,
      system: systemPromptForChat(noteContext),
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

  const response = await routedSendMessage(
    'generate_title',
    `Generate a short title for this note:\n\n${content}`,
    { maxTokens: 30, system: GENERATE_TITLE_SYSTEM, claudeModel: AI_MODEL }
  );

  logUsage({ supabase, userId, action: 'title_gen', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

async function handleGenerateTags(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const content = body.content as string;
  if (!content) {
    return errorResponse('INVALID_REQUEST', 'content is required');
  }

  const response = await routedSendMessage(
    'generate_tags',
    `Extract keyword tags from this note:\n\n${content}`,
    { maxTokens: 50, system: GENERATE_TAGS_SYSTEM, claudeModel: AI_MODEL }
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
  const response = await routedSendMessage(
    'extract_temporal_echoes',
    `Notes:\n${noteSummaries}\n\nHandles:\n${handles || ''}`,
    { maxTokens: 512, system: systemPromptForTemporalEchoes(todayISO), claudeModel: AI_MODEL }
  );

  logUsage({ supabase, userId, action: 'temporal_echo', inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, model: response.model }).catch(() => {});

  return jsonResponse({ text: response.content });
}

async function handleExtractEntities(body: ActionRequest, userId: string, supabase: SupabaseClient) {
  const sectionsText = body.sectionsText as string;
  if (!sectionsText) {
    return errorResponse('INVALID_REQUEST', 'sectionsText is required');
  }

  const response = await routedSendMessage(
    'extract_entities',
    sectionsText,
    { maxTokens: 256, system: EXTRACT_ENTITIES_SYSTEM, claudeModel: AI_MODEL }
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
