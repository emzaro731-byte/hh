import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const systemPrompt = `You are VEYLORA AI, a highly capable general-purpose AI assistant.
Be accurate, thoughtful, useful, concise when simple and deeply explanatory when needed.
Reason through difficult problems before answering. Help with coding, writing, business, learning, research, planning and creative work.
When the user asks for code, provide production-quality code and explain important assumptions.
Never claim to have performed an action you did not perform. If information may be current or uncertain, say so.
Preserve conversation context and directly answer the user's actual request.`;

const allowedModels = new Set([
  'groq/compound',
  'openai/gpt-oss-120b',
  'openai/gpt-oss-20b',
  'qwen/qwen3.6-27b',
  'llama-3.3-70b-versatile',
]);

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const body = await req.json();
    const incoming = Array.isArray(body.messages) ? body.messages : [];
    if (incoming.length === 0) throw new Error('At least one chat message is required.');

    const requestedModel = typeof body.model === 'string' ? body.model : 'groq/compound';
    const model = allowedModels.has(requestedModel) ? requestedModel : 'groq/compound';

    const messages = [
      { role: 'system', content: systemPrompt },
      ...incoming.filter((m: unknown) => {
        if (!m || typeof m !== 'object') return false;
        const x = m as Record<string, unknown>;
        return ['system', 'user', 'assistant'].includes(String(x.role)) && typeof x.content === 'string';
      }),
    ];

    const key = Deno.env.get('GROQ_API_KEY');
    if (!key) throw new Error('GROQ_API_KEY is not configured in Supabase.');

    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages,
        temperature: 0.7,
        max_completion_tokens: 8192,
        stream: false,
      }),
    });

    const responseBody = await response.text();
    return new Response(responseBody, {
      status: response.status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
