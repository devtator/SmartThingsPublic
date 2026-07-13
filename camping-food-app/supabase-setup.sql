-- Campfire Kitchen database setup (v5).
-- v4: users may sign in with a phone number OR an email (or link
-- both to one account) — chef checks and order ownership accept
-- either identity.
-- v5: campers also can't touch the day-cycle settings — order
-- history, the current day, the cutoff time, or the open/closed
-- override are chef-only.
-- Run this in your Supabase project's SQL editor
-- (Dashboard → SQL Editor → New query → paste → Run).
-- Safe to re-run: it drops and recreates its own policies/functions.
--
-- v3 moves the chef checks SERVER-SIDE:
--  * campfire_chefs table lists the chefs' verified phone numbers.
--  * All writes go through the campfire_write / campfire_seed
--    functions, which validate the caller: only chefs may change
--    menus, confirm/serve orders belonging to others, edit the camp
--    site directory, or create camp sites. Campers may only add or
--    change their OWN orders (matched to their verified phone).
--  * Direct INSERT/UPDATE on the table are no longer allowed —
--    even a tampered client can't bypass the rules.

-- ------------------------------------------------------------------
-- Data table: one JSONB row per camp site (row 0 = site directory,
-- row 1 = Demo Campground). `version` powers optimistic concurrency.
create table if not exists public.campfire_state (
  id      integer primary key,
  version bigint  not null default 1,
  data    jsonb   not null
);
alter table public.campfire_state enable row level security;

-- Chefs, by verified phone number (E.164). Add more chefs with:
--   insert into public.campfire_chefs (phone) values ('+1XXXXXXXXXX');
create table if not exists public.campfire_chefs (
  phone text primary key
);
alter table public.campfire_chefs enable row level security;
-- (No policies on purpose: only the security-definer functions below
-- read it, so the chef list is not directly visible to clients.)

insert into public.campfire_chefs (phone) values
  ('+16175298470'),
  ('brylong@gmail.com')
on conflict do nothing;

-- ------------------------------------------------------------------
-- Policies: signed-in users can READ everything. All writes must go
-- through the functions below, so the old write policies are dropped
-- and not recreated.
drop policy if exists "campfire anon select"  on public.campfire_state;
drop policy if exists "campfire anon insert"  on public.campfire_state;
drop policy if exists "campfire anon update"  on public.campfire_state;
drop policy if exists "campfire auth select"  on public.campfire_state;
drop policy if exists "campfire auth insert"  on public.campfire_state;
drop policy if exists "campfire auth update"  on public.campfire_state;

create policy "campfire auth select" on public.campfire_state
  for select to authenticated using (true);

-- ------------------------------------------------------------------
-- Helpers
-- Every identity attached to the signed-in user: their verified
-- phone (as +E.164) and/or their email (lowercased). A user needs
-- only one, but may link both.
create or replace function public.jwt_ids()
returns text[]
language sql stable
as $$
  select array_remove(array[
    case
      when coalesce(auth.jwt()->>'phone', '') = '' then null
      else '+' || ltrim(auth.jwt()->>'phone', '+')
    end,
    nullif(lower(coalesce(auth.jwt()->>'email', '')), '')
  ], null);
$$;

drop function if exists public.jwt_phone();

-- The campfire_chefs.phone column holds either a phone (+E.164) or
-- a lowercase email — whichever identity the chef signs in with.
create or replace function public.campfire_is_chef()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from campfire_chefs c where c.phone = any (public.jwt_ids())
  );
$$;

-- ------------------------------------------------------------------
-- campfire_seed: create a row if it doesn't exist; returns its
-- current version either way. Anyone signed in may seed the
-- directory (0) and Demo Campground (1) on first boot; other rows
-- require the caller to be a chef or the site to already be listed
-- in the directory (covers a camper racing a just-created site).
create or replace function public.campfire_seed(p_id integer, p_data jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_dir jsonb;
  v_version bigint;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'sign in required';
  end if;
  if p_id is null or p_id < 0 or p_data is null then
    raise exception 'bad request';
  end if;
  if p_id > 1 and not public.campfire_is_chef() then
    select data into v_dir from campfire_state where id = 0;
    if v_dir is null or not exists (
      select 1 from jsonb_array_elements(coalesce(v_dir->'sites', '[]'::jsonb)) s
      where (s->>'id')::int = p_id
    ) then
      raise exception 'only the chef can create camp sites';
    end if;
  end if;
  insert into campfire_state (id, version, data) values (p_id, 1, p_data)
  on conflict (id) do nothing;
  select version into v_version from campfire_state where id = p_id;
  return v_version;
end;
$$;

-- ------------------------------------------------------------------
-- campfire_write: the only way to update a row. Returns the new
-- version on success, or -1 when someone else wrote first (the
-- client re-fetches and retries). Chefs may change anything;
-- campers may not touch the menu, the directory, or anyone else's
-- orders.
create or replace function public.campfire_write(
  p_id integer, p_expected_version bigint, p_data jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_ids  text[]  := public.jwt_ids();
  v_chef boolean := public.campfire_is_chef();
  v_old   campfire_state%rowtype;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'sign in required';
  end if;
  if p_id is null or p_id < 0 or p_data is null then
    raise exception 'bad request';
  end if;

  select * into v_old from campfire_state where id = p_id for update;
  if not found then
    raise exception 'no such camp site';
  end if;
  if v_old.version is distinct from p_expected_version then
    return -1; -- concurrent write: client refetches and retries
  end if;

  if not v_chef then
    if p_id = 0 then
      raise exception 'only the chef can change the camp site list';
    end if;
    if (v_old.data->'meals') is distinct from (p_data->'meals') then
      raise exception 'only the chef can change the menu';
    end if;
    if coalesce(v_old.data->'history', '[]'::jsonb) is distinct from coalesce(p_data->'history', '[]'::jsonb)
       or (v_old.data->'day') is distinct from (p_data->'day')
       or coalesce(v_old.data->'cutoffTime', '""'::jsonb) is distinct from coalesce(p_data->'cutoffTime', '""'::jsonb)
       or coalesce(v_old.data->'orderingOverride', 'null'::jsonb) is distinct from coalesce(p_data->'orderingOverride', 'null'::jsonb) then
      raise exception 'only the chef can change kitchen settings';
    end if;
    if exists (
      with old_orders as (
        select value->>'id' as id, value as v
        from jsonb_array_elements(coalesce(v_old.data->'orders', '[]'::jsonb))
      ),
      new_orders as (
        select value->>'id' as id, value as v
        from jsonb_array_elements(coalesce(p_data->'orders', '[]'::jsonb))
      ),
      changed as (
        select o.v as ov, n.v as nv
        from old_orders o
        full outer join new_orders n using (id)
        where o.v is distinct from n.v
      )
      select 1 from changed
      where (ov is not null and not coalesce(ov->>'camperId', '') = any (v_ids))
         or (nv is not null and not coalesce(nv->>'camperId', '') = any (v_ids))
    ) then
      raise exception 'you can only change your own orders';
    end if;
  end if;

  update campfire_state
     set version = v_old.version + 1, data = p_data
   where id = p_id;
  return v_old.version + 1;
end;
$$;

-- ------------------------------------------------------------------
-- Only signed-in users may call the functions.
revoke all on function public.campfire_is_chef() from public, anon;
revoke all on function public.campfire_seed(integer, jsonb) from public, anon;
revoke all on function public.campfire_write(integer, bigint, jsonb) from public, anon;
grant execute on function public.campfire_is_chef() to authenticated;
grant execute on function public.campfire_seed(integer, jsonb) to authenticated;
grant execute on function public.campfire_write(integer, bigint, jsonb) to authenticated;
