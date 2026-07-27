import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Content-Type": "application/json",
};

function publishableKey(): string | undefined {
  const legacy = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    return Object.values(keys)[0] as string | undefined;
  } catch {
    return undefined;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: cors,
    });
  }

  const authorization = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const key = publishableKey();
  if (!authorization || !supabaseUrl || !key) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: cors,
    });
  }

  const supabase = createClient(supabaseUrl, key, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: cors,
    });
  }

  const turnKeyId = Deno.env.get("CLOUDFLARE_TURN_KEY_ID");
  const turnApiToken = Deno.env.get("CLOUDFLARE_TURN_API_TOKEN");
  if (!turnKeyId || !turnApiToken) {
    // Calls stay feature-flagged off until these production secrets exist.
    return new Response(
      JSON.stringify({ error: "turn_not_configured", retryable: false }),
      { status: 503, headers: cors },
    );
  }

  const ttl = 60 * 60;
  const response = await fetch(
    `https://rtc.live.cloudflare.com/v1/turn/keys/${turnKeyId}/credentials/generate-ice-servers`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${turnApiToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ttl }),
    },
  );

  if (!response.ok) {
    console.error("Cloudflare TURN credential request failed", response.status);
    return new Response(
      JSON.stringify({ error: "turn_provider_unavailable", retryable: true }),
      { status: 503, headers: cors },
    );
  }

  const payload = await response.json();
  return new Response(
    JSON.stringify({
      iceServers: payload.iceServers ?? [],
      expiresIn: ttl,
    }),
    { status: 201, headers: cors },
  );
});
