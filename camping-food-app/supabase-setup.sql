-- Campfire Kitchen shared-state table.
-- Run this once in your Supabase project's SQL editor
-- (Dashboard → SQL Editor → New query → paste → Run).
--
-- The app keeps all shared data (meals, orders, notifications) in a
-- single JSONB row and uses the `version` column for optimistic
-- concurrency: writers only succeed if the version they read is
-- still current, otherwise they re-fetch and re-apply.

create table if not exists public.campfire_state (
  id      integer primary key,
  version bigint  not null default 1,
  data    jsonb   not null
);

alter table public.campfire_state enable row level security;

-- Demo-grade access: anyone with the anon key can read and write.
-- Good enough for a campsite pilot; see README caveats before using
-- this for anything beyond that.
create policy "campfire anon select" on public.campfire_state
  for select to anon using (true);
create policy "campfire anon insert" on public.campfire_state
  for insert to anon with check (id = 1);
create policy "campfire anon update" on public.campfire_state
  for update to anon using (id = 1) with check (id = 1);
