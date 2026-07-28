// KLECT — push-fanout
//
// Invoked by a Database Webhook on INSERT into public.notifications.
// Looks up the recipient's device tokens and delivers via FCM v1 (Android + iOS both go
// through FCM). Prunes tokens that FCM reports as permanently dead.
//
// verify_jwt is false because Supabase Database Webhooks do not carry a user JWT. The function
// is instead authenticated by a shared secret header that only the webhook config knows.
//
// REQUIRED SECRETS (set these before it will send anything):
//   PUSH_WEBHOOK_SECRET     — any long random string; must match the webhook's x-klect-secret header
//   FCM_SERVICE_ACCOUNT     — the full Firebase service-account JSON, as one line
// Until FCM_SERVICE_ACCOUNT is set the function is a graceful no-op: it returns 200 with
// {skipped:"fcm-not-configured"} so the webhook never retries in a loop.
//
// (Source recovered 2026-07-27 from the deployed version 1 via MCP get_edge_function —
// it was deployed-but-unversioned. This file is now the source of truth.)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type NotificationRow = {
  id: string;
  user_id: string;
  actor_id: string | null;
  type: string;
  entity_type: string | null;
  entity_id: string | null;
  conversation_id: string | null;
  body: string | null;
};

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// ── copy shown in the notification tray, per notification_type ──
function compose(n: NotificationRow, actor: string) {
  switch (n.type) {
    case "like":    return { title: actor, body: `liked your ${n.entity_type ?? "post"}` };
    case "save":    return { title: actor, body: `saved your ${n.entity_type ?? "post"}` };
    case "repost":  return { title: actor, body: `reposted your ${n.entity_type ?? "post"}` };
    case "comment": return { title: actor, body: n.body ?? "commented on your post" };
    case "reply":   return { title: actor, body: n.body ?? "replied to you" };
    case "mention": return { title: actor, body: n.body ?? "mentioned you" };
    case "follow":  return { title: actor, body: "started following you" };
    case "message": return { title: actor, body: n.body ?? "sent you a message" };
    case "call":    return { title: actor, body: "is calling you" };
    case "match":   return { title: "New match", body: `You and ${actor} collect the same things` };
    case "moderation": return { title: "Klect", body: n.body ?? "An update about your content" };
    default:        return { title: "Klect", body: n.body ?? "You have a new notification" };
  }
}

// deep link the client resolves into a route
function linkFor(n: NotificationRow): string {
  if (n.conversation_id) return `klect://messages/${n.conversation_id}`;
  if (n.entity_type && n.entity_id) return `klect://closeup/${n.entity_type}/${n.entity_id}`;
  if (n.type === "follow" && n.actor_id) return `klect://u/${n.actor_id}`;
  return "klect://notifications";
}

// ── minimal RS256 JWT -> OAuth2 access token for FCM ──
function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(new TextEncoder().encode(JSON.stringify({
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));

  const pem = sa.private_key.replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`),
  ));

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token as string;
}

Deno.serve(async (req: Request) => {
  try {
    const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
    if (!secret || req.headers.get("x-klect-secret") !== secret) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    const payload = await req.json();
    const n: NotificationRow | undefined = payload?.record ?? payload?.new ?? payload;
    if (!n?.user_id) {
      return new Response(JSON.stringify({ error: "no notification row in payload" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) {
      // Deliberate: return 200 so the webhook does not retry forever before FCM is configured.
      return new Response(JSON.stringify({ skipped: "fcm-not-configured" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    const { data: tokens } = await supabase
      .from("push_tokens")
      .select("token, platform")
      .eq("user_id", n.user_id)
      .eq("enabled", true);
    if (!tokens?.length) {
      return new Response(JSON.stringify({ sent: 0, reason: "no-devices" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    // Respect a muted conversation even if the row slipped through.
    if (n.conversation_id) {
      const { data: member } = await supabase
        .from("conversation_members").select("muted_until")
        .eq("conversation_id", n.conversation_id).eq("user_id", n.user_id).maybeSingle();
      if (member?.muted_until && new Date(member.muted_until) > new Date()) {
        return new Response(JSON.stringify({ sent: 0, reason: "muted" }), {
          status: 200, headers: { "Content-Type": "application/json" },
        });
      }
    }

    let actorName = "Someone";
    if (n.actor_id) {
      const { data: actor } = await supabase
        .from("profiles").select("display_name").eq("id", n.actor_id).maybeSingle();
      if (actor?.display_name) actorName = actor.display_name;
    }

    const sa = JSON.parse(saRaw) as { client_email: string; private_key: string; project_id: string };
    const token = await accessToken(sa);
    const { title, body } = compose(n, actorName);
    const link = linkFor(n);
    const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    const dead: string[] = [];
    let sent = 0;

    await Promise.all(tokens.map(async (t: { token: string; platform: string }) => {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: t.token,
            notification: { title, body },
            data: { link, type: n.type, notification_id: n.id },
            android: { priority: n.type === "call" ? "HIGH" : "NORMAL", notification: { channel_id: n.type === "call" ? "calls" : "social" } },
            apns: {
              headers: { "apns-priority": n.type === "call" ? "10" : "5" },
              payload: { aps: { sound: n.type === "call" ? "ringtone.caf" : "default", "thread-id": n.conversation_id ?? n.type } },
            },
          },
        }),
      });
      if (res.ok) { sent++; return; }
      // 404 UNREGISTERED / 400 INVALID_ARGUMENT mean the token will never work again.
      if (res.status === 404 || res.status === 400) dead.push(t.token);
    }));

    if (dead.length) await supabase.from("push_tokens").delete().in("token", dead);

    return new Response(JSON.stringify({ sent, pruned: dead.length }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("push-fanout failed", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
