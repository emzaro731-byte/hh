import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const allowedModels = new Set([
  'openai/gpt-oss-120b',
  'openai/gpt-oss-20b',
  'qwen/qwen3.6-27b',
  'groq/compound',
]);

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }

  try {
    const body = await req.json();
    const messages = Array.isArray(body.messages) ? body.messages : [];
    const requestedModel = typeof body.model === 'string'
      ? body.model
      : 'openai/gpt-oss-120b';
    const model = allowedModels.has(requestedModel)
      ? requestedModel
      : 'openai/gpt-oss-120b';

    if (messages.length === 0) {
      throw new Error('At least one chat message is required.');
    }

    const key = Deno.env.get('GROQ_API_KEY');
    if (!key) {
      throw new Error('GROQ_API_KEY is not configured in Supabase.');
    }

    const response = await fetch(
      'https://api.groq.com/openai/v1/chat/completions',
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: 0.7,
        }),
      },
    );

    const responseBody = await response.text();
    return new Response(responseBody, {
      status: response.status,
      headers: {
        ...cors,
        'Content-Type': 'application/json',
      },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: {
          ...cors,
          'Content-Type': 'application/json',
        },
      },
    );
  }
});
