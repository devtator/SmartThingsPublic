-- Campfire Kitchen shared-state table + access policies.
-- Run this once in your Supabase project's SQL editor
-- (Dashboard → SQL Editor → New query → paste → Run).
-- Safe to re-run: it drops and recreates its own policies.
--
-- The app stores one JSONB row per camp site (row 0 is the directory
-- of camp sites, row 1 is the Demo Campground, new sites get the next
-- id) and uses the `version` column for optimistic concurrency:
-- writers only succeed if the version they read is still current,
-- otherwise they re-fetch and re-apply.
--
-- Access requires sign-in: users authenticate with their cell number
-- via Supabase Auth SMS codes, and only the `authenticated` role can
-- read or write. (Remember to enable the Phone provider and an SMS
-- sender under Authentication → Sign In / Up → Phone — see README.)

create table if not exists public.campfire_state (
  id      integer primary key,
  version bigint  not null default 1,
  data    jsonb   not null
);

alter table public.campfire_state enable row level security;

-- Remove the older anon-access policies if they exist.
drop policy if exists "campfire anon select" on public.campfire_state;
drop policy if exists "campfire anon insert" on public.campfire_state;
drop policy if exists "campfire anon update" on public.campfire_state;

-- Phone-verified (signed-in) users can read and write the shared row.
drop policy if exists "campfire auth select" on public.campfire_state;
drop policy if exists "campfire auth insert" on public.campfire_state;
drop policy if exists "campfire auth update" on public.campfire_state;

create policy "campfire auth select" on public.campfire_state
  for select to authenticated using (true);
create policy "campfire auth insert" on public.campfire_state
  for insert to authenticated with check (id >= 0);
create policy "campfire auth update" on public.campfire_state
  for update to authenticated using (id >= 0) with check (id >= 0);
