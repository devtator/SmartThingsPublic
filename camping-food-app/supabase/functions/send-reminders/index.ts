// Campfire Kitchen — send-reminders Edge Function.
//
// Invoked on a schedule (see supabase-cron.sql, every 10 minutes).
// For every camp site with an evening cutoff, when the cutoff is
// less than an hour away it reminds each invited camper who hasn't
// ordered tomorrow's breakfast yet — by EMAIL when we have one, by
// TEXT for contacts with no email on file. Each cutoff is reminded
// at most once (tracked on the site's directory entry).
//
// Deploy (dashboard): Edge Functions → Deploy a new function →
//   name it exactly `send-reminders` → paste this file → Deploy →
//   in the function's settings, turn OFF "Enforce JWT verification"
//   (the cron caller authenticates with the shared secret below).
// Secrets (in addition to the send-invites Twilio/Resend secrets):
//   CRON_SECRET — any random string; must match supabase-cron.sql
//   SITE_URL    — e.g. https://devtator.github.io/SmartThingsPublic/

import { createClient } from "npm:@supabase/supabase-js@2";

const LEAD_MS = 60 * 60 * 1000; // remind when less than 1 hour remains

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function cutoffLabel(v: string): string {
  if (v === "24:00") return "midnight";
  const [h, m] = v.split(":").map(Number);
  return `${((h + 11) % 12) + 1}:${String(m || 0).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

// First occurrence of the cutoff time (chef-local) after the day
// started, as an epoch. tzOffsetMin is Date.getTimezoneOffset() as
// recorded on the chef's device (minutes; positive west of UTC).
function cutoffEpoch(data: Record<string, unknown>): number | null {
  const day = (data.day ?? {}) as { startedAt?: number; tzOffsetMin?: number };
  const cutoff = data.cutoffTime as string | undefined;
  if (!cutoff || !day.startedAt) return null;
  const off = (day.tzOffsetMin ?? 0) * 60000;
  const [h, m] = cutoff.split(":").map(Number);
  const local = new Date(day.startedAt - off); // UTC getters now read chef-local wall clock
  local.setUTCHours(h, m || 0, 0, 0);
  if (local.getTime() <= day.startedAt - off) local.setUTCDate(local.getUTCDate() + 1);
  return local.getTime() + off;
}

async function sendSms(to: string, message: string): Promise<{ ok: boolean; error?: string }> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_FROM");
  const svc = Deno.env.get("TWILIO_MESSAGING_SERVICE_SID");
  if (!sid || !token || (!from && !svc)) return { ok: false, error: "Twilio secrets not configured" };
  const form = new URLSearchParams({
    To: to, Body: message,
    ...(svc ? { MessagingServiceSid: svc } : { From: from! }),
  });
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: "Basic " + btoa(`${sid}:${token}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
  });
  const j = await r.json().catch(() => ({} as Record<string, unknown>));
  return { ok: r.ok, error: r.ok ? undefined : String(j.message ?? `Twilio ${r.status}`) };
}

async function sendEmail(to: string, subject: string, message: string): Promise<{ ok: boolean; error?: string }> {
  const key = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM");
  if (!key || !from) return { ok: false, error: "Resend secrets not configured" };
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [to], subject, text: message }),
  });
  const j = await r.json().catch(() => ({} as Record<string, unknown>));
  return { ok: r.ok, error: r.ok ? undefined : String(j.message ?? `Resend ${r.status}`) };
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "forbidden" }, 403);
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // server-side only; bypasses RLS for the sweep
  );

  const { data: rows, error } = await db.from("campfire_state").select("id,version,data");
  if (error) return json({ error: error.message }, 500);
  const dir = rows?.find((r) => r.id === 0);
  if (!dir) return json({ report: [], note: "no directory yet" });

  const now = Date.now();
  const siteUrl = (Deno.env.get("SITE_URL") ?? "").replace(/\/$/, "");
  const report: unknown[] = [];
  let dirChanged = false;

  for (const site of (dir.data.sites ?? []) as Record<string, unknown>[]) {
    const row = rows!.find((r) => r.id === site.id);
    if (!row) continue;
    const d = row.data as Record<string, unknown>;
    if (d.orderingOverride === "closed") continue; // chef already closed up
    const cutoff = cutoffEpoch(d);
    if (!cutoff || now < cutoff - LEAD_MS || now >= cutoff) continue;
    if (site.lastReminderFor === cutoff) continue; // already reminded for this cutoff

    // Invited contacts who don't have an order in for tomorrow.
    const ordered = new Set(
      ((d.orders ?? []) as Record<string, unknown>[]).map((o) => String(o.camperId ?? "").toLowerCase()),
    );
    const members = (site.members ?? []) as string[]; // invite-link joiners
    const allEmails = [...new Set([...(site.emails ?? []) as string[], ...members.filter((m) => m.includes("@"))]
      .map((e) => e.toLowerCase()))];
    const allPhones = [...new Set([...(site.phones ?? []) as string[], ...members.filter((m) => m.startsWith("+"))])];
    const emails = allEmails.filter((e) => !ordered.has(e));
    const phones = allPhones.filter((p) => !ordered.has(p.toLowerCase()));

    const link = siteUrl ? `${siteUrl}/?site=${site.id}` : "";
    const label = cutoffLabel(String(d.cutoffTime));
    const message = `⏰ Last call from ${site.name}'s camp kitchen: order tomorrow's breakfast before ${label}!${link ? " " + link : ""}`;
    const results: unknown[] = [];
    for (const to of emails.slice(0, 50)) {
      results.push({ to, ...(await sendEmail(to, "⏰ Breakfast orders close soon", message)) });
    }
    for (const to of phones.slice(0, 50)) {
      results.push({ to, ...(await sendSms(to, message)) });
    }

    site.lastReminderFor = cutoff;
    dirChanged = true;
    report.push({ site: site.id, cutoff, results });
  }

  if (dirChanged) {
    // Optimistic write; if a client wrote concurrently we just skip —
    // the next cron tick retries within the reminder window.
    await db.from("campfire_state")
      .update({ version: (dir.version as number) + 1, data: dir.data })
      .eq("id", 0)
      .eq("version", dir.version);
  }

  return json({ report }, 200);
});
