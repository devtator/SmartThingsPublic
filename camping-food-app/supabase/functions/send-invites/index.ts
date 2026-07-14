// Campfire Kitchen — send-invites Edge Function.
//
// Sends camp-site invite texts (Twilio) and welcome emails (your
// SMTP provider, or Resend as a fallback), keeping all credentials
// server-side (Supabase secrets) instead of in the public config.js.
// Only signed-in chefs (per the campfire_chefs table, checked via
// the campfire_is_chef RPC) may call it.
//
// Deploy (dashboard): Edge Functions → Deploy a new function →
//   name it exactly `send-invites` → paste this file → Deploy.
// Secrets (Edge Functions → Secrets, or `supabase secrets set`):
//   TWILIO_ACCOUNT_SID          — from the Twilio console
//   TWILIO_AUTH_TOKEN           — from the Twilio console
//   TWILIO_FROM                 — your Twilio phone number (+1…)
//     …or TWILIO_MESSAGING_SERVICE_SID instead of TWILIO_FROM.
//   Email — set EITHER an SMTP server (recommended; the same creds
//   you gave Supabase Auth's SMTP settings) OR Resend:
//   SMTP_HOST / SMTP_PORT / SMTP_USER / SMTP_PASS / SMTP_FROM
//     (port 465 = implicit TLS, 587 = STARTTLS; SMTP_FROM like
//      "Campfire Kitchen <chef@yourdomain.com>")
//   …or RESEND_API_KEY / RESEND_FROM (from resend.com).
//
// Every channel is independent: a missing/failed channel fails only
// its own recipients, each with a per-recipient error message.
//
// Request:  POST { phones: ["+1…"], emails: ["a@b.com"],
//                  subject: "…", message: "…" }
// Response: { results: [{ to, ok, error? }, …] }

import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

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

// Reject instead of hanging forever (a hung SMTP send otherwise gets
// killed as an opaque "EarlyDrop" with no useful error).
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, rej) => setTimeout(() => rej(new Error(`${label} timed out after ${ms}ms`)), ms)),
  ]);
}

// Send one email through SMTP when configured, else Resend. Returns
// a per-recipient {ok, error?} so one bad address never aborts the
// batch.
async function sendEmail(to: string, subject: string, message: string): Promise<{ ok: boolean; error?: string }> {
  const smtpHost = Deno.env.get("SMTP_HOST");
  if (smtpHost) {
    const from = Deno.env.get("SMTP_FROM") ?? Deno.env.get("RESEND_FROM");
    if (!from) return { ok: false, error: "SMTP_FROM not set" };
    const port = Number(Deno.env.get("SMTP_PORT") ?? "587");
    const username = Deno.env.get("SMTP_USER") ?? "";
    const password = Deno.env.get("SMTP_PASS") ?? "";
    const client = new SMTPClient({
      connection: {
        hostname: smtpHost,
        port,
        tls: port === 465, // implicit TLS on 465; 587 upgrades via STARTTLS
        auth: username ? { username, password } : undefined,
      },
    });
    try {
      await withTimeout(client.send({ from, to, subject, content: message }), 20000, "SMTP send");
      await client.close();
      console.log(`[email] sent to ${to} via SMTP (${smtpHost}:${port})`);
      return { ok: true };
    } catch (e) {
      try { await client.close(); } catch (_) { /* ignore */ }
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`[email] SMTP failed for ${to} (${smtpHost}:${port}): ${msg}`);
      return { ok: false, error: "SMTP: " + msg };
    }
  }
  const key = Deno.env.get("RESEND_API_KEY");
  const rFrom = Deno.env.get("RESEND_FROM");
  if (!key || !rFrom) return { ok: false, error: "No email provider configured (set SMTP_* or RESEND_*)" };
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: rFrom, to: [to], subject, text: message }),
  });
  const j = await r.json().catch(() => ({} as Record<string, unknown>));
  return { ok: r.ok, error: r.ok ? undefined : String(j.message ?? `Resend error ${r.status}`) };
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

    const body = await req.json().catch(() => ({}));
    const phones: string[] = Array.isArray(body.phones) ? body.phones : [];
    const emails: string[] = Array.isArray(body.emails) ? body.emails : [];
    const message: string = typeof body.message === "string" ? body.message : "";
    const subject: string = typeof body.subject === "string" && body.subject
      ? body.subject : "🏕️ You're invited to the camp kitchen";
    if ((phones.length === 0 && emails.length === 0) ||
        message.length === 0 || message.length > 500 || subject.length > 200) {
      return json({ error: "bad request: expected { phones and/or emails, message }" }, 400);
    }

    const results: { to: string; ok: boolean; error?: string }[] = [];

    // --- SMS invites via Twilio ---
    const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const token = Deno.env.get("TWILIO_AUTH_TOKEN");
    const from = Deno.env.get("TWILIO_FROM");
    const svc = Deno.env.get("TWILIO_MESSAGING_SERVICE_SID");
    for (const to of phones.slice(0, 25)) { // sanity cap per call
      if (!/^\+\d{10,15}$/.test(String(to))) {
        results.push({ to: String(to), ok: false, error: "invalid phone format" });
        continue;
      }
      if (!sid || !token || (!from && !svc)) {
        results.push({ to: String(to), ok: false, error: "Twilio secrets not configured" });
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

    // --- Email invites via SMTP (or Resend fallback) ---
    for (const to of emails.slice(0, 25)) {
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(to))) {
        results.push({ to: String(to), ok: false, error: "invalid email format" });
        continue;
      }
      results.push({ to: String(to), ...(await sendEmail(String(to), subject, message)) });
    }

    console.log("[send-invites] results:", JSON.stringify(results));
    return json({ results }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
