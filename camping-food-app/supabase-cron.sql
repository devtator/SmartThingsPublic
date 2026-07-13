-- Campfire Kitchen — schedule the cutoff reminders.
-- Run once in the Supabase SQL Editor AFTER deploying the
-- send-reminders Edge Function (see its header for deploy steps).
--
-- Before running:
--  1. Replace CHANGE-ME-TO-A-RANDOM-STRING below with any random
--     string, and set the SAME value as the CRON_SECRET secret on
--     the Edge Function (Edge Functions → Secrets).
--  2. In the send-reminders function settings, turn OFF
--     "Enforce JWT verification" (the secret header is the guard).
--
-- This checks every 10 minutes; reminders go out when a camp site's
-- cutoff is less than an hour away, once per cutoff.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Re-running this file replaces the existing schedule.
select cron.unschedule('campfire-reminders')
where exists (select 1 from cron.job where jobname = 'campfire-reminders');

select cron.schedule(
  'campfire-reminders',
  '*/10 * * * *',
  $$
  select net.http_post(
    url     := 'https://ocqtujgxftdbjuuhrlxl.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', 'CHANGE-ME-TO-A-RANDOM-STRING'
    ),
    body    := '{}'::jsonb
  );
  $$
);
