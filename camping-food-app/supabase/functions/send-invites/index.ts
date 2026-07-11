// Campfire Kitchen — send-invites Edge Function.
//
// Sends camp-site invite texts through Twilio, keeping the Twilio
// credentials server-side (Supabase secrets) instead of in the
// public config.js. Only signed-in chefs (per the campfire_chefs
// table, checked via the campfire_is_chef RPC) may call it.
//
// Deploy (dashboard): Edge Functions → Deploy a new function →
//   name it exactly `send-invites` → paste this file → Deploy.
// Secrets (Edge Functions → Secrets, or `supabase secrets set`):
//   TWILIO_ACCOUNT_SID          — from the Twilio console
//   TWILIO_AUTH_TOKEN           — from the Twilio console
//   TWILIO_FROM                 — your Twilio phone number (+1…)
//     …or TWILIO_MESSAGING_SERVICE_SID instead of TWILIO_FROM.
//
// Request:  POST { phones: ["+1…", …], message: "…" }
// Response: { results: [{ to, ok, error? }, …] }

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    // Verify the caller is a signed-in chef by evaluating the
    // campfire_is_chef RPC with the caller's own JWT.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data: isChef, error: chefErr } = await supabase.rpc("campfire_is_chef");
    if (chefErr || isChef !== true) {
      return json({ error: "Only the chef can send invites" }, 403);
    }

    const { phones, message } = await req.json().catch(() => ({}));
    if (!Array.isArray(phones) || phones.length === 0 ||
        typeof message !== "string" || message.length === 0 || message.length > 500) {
      return json({ error: "bad request: expected { phones: [...], message } " }, 400);
    }

    const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const token = Deno.env.get("TWILIO_AUTH_TOKEN");
    const from = Deno.env.get("TWILIO_FROM");
    const svc = Deno.env.get("TWILIO_MESSAGING_SERVICE_SID");
    if (!sid || !token || (!from && !svc)) {
      return json({ error: "Twilio secrets are not configured on the server" }, 500);
    }

    const results: { to: string; ok: boolean; error?: string }[] = [];
    for (const to of phones.slice(0, 25)) { // sanity cap per call
      if (!/^\+\d{10,15}$/.test(String(to))) {
        results.push({ to: String(to), ok: false, error: "invalid phone format" });
        continue;
      }
      const form = new URLSearchParams({
        To: String(to),
        Body: message,
        ...(svc ? { MessagingServiceSid: svc } : { From: from! }),
      });
      const r = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
        {
          method: "POST",
          headers: {
            Authorization: "Basic " + btoa(`${sid}:${token}`),
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: form,
        },
      );
      const j = await r.json().catch(() => ({} as Record<string, unknown>));
      results.push({
        to: String(to),
        ok: r.ok,
        error: r.ok ? undefined : String(j.message ?? `Twilio error ${r.status}`),
      });
    }
    return json({ results }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
