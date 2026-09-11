import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (x: any, status = 200) =>
  new Response(JSON.stringify(x), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

function b64url(input: Uint8Array | string) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function googleAccessToken() {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
  const privateKey = (Deno.env.get('FIREBASE_PRIVATE_KEY') || '').replace(/\\n/g, '\n');

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error('Firebase service account secrets are not configured');
  }

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(
    JSON.stringify({
      iss: clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const pem = privateKey.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const raw = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    raw,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const sig = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(`${header}.${claim}`),
    ),
  );

  const jwt = `${header}.${claim}.${b64url(sig)}`;
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(tokenJson.error_description || 'Could not obtain Firebase access token');
  }

  return { projectId, accessToken: tokenJson.access_token as string };
}

serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const auth = req.headers.get('Authorization');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!auth || !serviceKey) return json({ error: 'Unauthorized' }, 401);

    const service = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey, {
      global: { headers: { Authorization: auth } },
    });

    const { data: { user }, error: userError } = await service.auth.getUser();
    if (userError || !user) return json({ error: 'Unauthorized' }, 401);

    const { callId } = await req.json();
    if (!callId) return json({ error: 'callId is required' }, 400);

    const { data: call, error: callError } = await service
      .from('calls')
      .select('id,caller_id,callee_id,type,status')
      .eq('id', callId)
      .single();

    if (callError || !call) return json({ error: 'Call not found' }, 404);
    if (call.caller_id !== user.id) {
      return json({ error: 'Only the caller can send the incoming call push' }, 403);
    }
    if (call.status !== 'ringing') return json({ error: 'Call is no longer ringing' }, 409);

    const [{ data: tokens, error: tokenError }, { data: caller }] = await Promise.all([
      service.from('device_tokens').select('token').eq('user_id', call.callee_id),
      service.from('profiles').select('display_name').eq('id', call.caller_id).single(),
    ]);

    if (tokenError) throw tokenError;

    const deviceTokens = (tokens || [])
      .map((x: any) => x.token)
      .filter(Boolean);

    if (!deviceTokens.length) {
      return json({ sent: 0, message: 'Callee has no registered push token' });
    }

    const { projectId, accessToken } = await googleAccessToken();
    const callerName = caller?.display_name || 'GG User';
    const results: any[] = [];

    for (const token of deviceTokens) {
      const message = {
        message: {
          token,
          notification: {
            title: `Incoming ${call.type === 'video' ? 'video' : 'voice'} call`,
            body: `${callerName} is calling you`,
          },
          data: {
            type: 'incoming_call',
            callId: call.id,
            callerId: call.caller_id,
            callerName,
            callType: call.type,
          },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'gg-incoming-calls',
              sound: 'default',
              notification_priority: 'PRIORITY_MAX',
              default_sound: true,
              default_vibrate_timings: true,
              sticky: true,
              tag: `call-${call.id}`,
            },
          },
          apns: {
            headers: {
              'apns-priority': '10',
              'apns-push-type': 'alert',
            },
            payload: {
              aps: {
                sound: 'default',
                content_available: true,
              },
            },
          },
        },
      };

      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(message),
        },
      );

      const body = await response.json().catch(() => ({}));
      results.push({
        token: token.slice(0, 8),
        ok: response.ok,
        error: response.ok ? undefined : body,
      });

      if (response.status === 404 || response.status === 410) {
        await service.from('device_tokens').delete().eq('token', token);
      }
    }

    return json({
      sent: results.filter(x => x.ok).length,
      results,
    });
  } catch (e) {
    return json({
      error: e instanceof Error ? e.message : 'Could not send call push',
    }, 500);
  }
});
