-- Campfire Kitchen database setup (v6).
-- v4: users may sign in with a phone number OR an email (or link
-- both to one account) — chef checks and order ownership accept
-- either identity.
-- v5: campers also can't touch the day-cycle settings — order
-- history, the current day, the cutoff time, or the open/closed
-- override are chef-only.
-- v6: PER-SITE MEMBERSHIP & CHEFS.
--  * A camp site's data is readable only by its members: invited
--    contacts, link-joiners (campfire_join), the site's chefs, and
--    global chefs. The directory (row 0) and the Demo Campground
--    (row 1) stay readable by all signed-in users.
--  * Each site may list multiple site chefs (its `chefs` array,
--    plus its creator implicitly). Site chefs have full chef powers
--    for THEIR site's row, and may edit their own site's directory
--    entry (contacts/chefs). Only global chefs (campfire_chefs)
--    create sites or touch other sites' entries.
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
-- Policies: signed-in users can read the directory and the Demo
-- Campground; other site rows are member-only. All writes go through
-- the functions below.
drop policy if exists "campfire anon select"  on public.campfire_state;
drop policy if exists "campfire anon insert"  on public.campfire_state;
drop policy if exists "campfire anon update"  on public.campfire_state;
drop policy if exists "campfire auth select"  on public.campfire_state;
drop policy if exists "campfire auth insert"  on public.campfire_state;
drop policy if exists "campfire auth update"  on public.campfire_state;

-- (The select policy itself is created at the END of this file — it
-- depends on the helper functions defined below.)

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
-- These are GLOBAL chefs: full powers on every camp site.
create or replace function public.campfire_is_chef()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from campfire_chefs c where c.phone = any (public.jwt_ids())
  );
$$;

-- The caller is a SITE CHEF of the given site: listed in the site's
-- `chefs` array, or its creator.
create or replace function public.campfire_is_site_chef(p_site_id integer)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from campfire_state d,
         jsonb_array_elements(coalesce(d.data->'sites', '[]'::jsonb)) s
    where d.id = 0
      and (s->>'id')::int = p_site_id
      and (
        lower(coalesce(s->>'createdBy', '')) in (select lower(x) from unnest(public.jwt_ids()) x)
        or exists (
          select 1 from jsonb_array_elements_text(coalesce(s->'chefs', '[]'::jsonb)) c
          where lower(c) in (select lower(x) from unnest(public.jwt_ids()) x)
        )
      )
  );
$$;

-- The caller is a MEMBER of the given site: an invited contact
-- (phones/emails), a link-joiner (members), a site chef, or the
-- creator.
create or replace function public.campfire_is_member(p_site_id integer)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from campfire_state d,
         jsonb_array_elements(coalesce(d.data->'sites', '[]'::jsonb)) s
    where d.id = 0
      and (s->>'id')::int = p_site_id
      and exists (
        select 1
        from (
          select jsonb_array_elements_text(coalesce(s->'phones', '[]'::jsonb)) as ident
          union all select jsonb_array_elements_text(coalesce(s->'emails', '[]'::jsonb))
          union all select jsonb_array_elements_text(coalesce(s->'members', '[]'::jsonb))
          union all select jsonb_array_elements_text(coalesce(s->'chefs', '[]'::jsonb))
          union all select coalesce(s->>'createdBy', '')
        ) ids
        where lower(ids.ident) in (select lower(x) from unnest(public.jwt_ids()) x)
      )
  );
$$;

-- campfire_join: enroll the signed-in user as a member of a camp
-- site. Called by the app when someone arrives via an invite link
-- (?site=N) — the link acts as the ticket in.
create or replace function public.campfire_join(p_site_id integer)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_dir   campfire_state%rowtype;
  v_ids   text[] := public.jwt_ids();
  v_sites jsonb;
  v_site  jsonb;
  v_members jsonb;
  v_idx   integer;
  v_changed boolean := false;
  v_id    text;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'sign in required';
  end if;
  select * into v_dir from campfire_state where id = 0 for update;
  if not found then
    raise exception 'no camp directory yet';
  end if;
  v_sites := coalesce(v_dir.data->'sites', '[]'::jsonb);
  select (t.i - 1)::integer into v_idx
  from jsonb_array_elements(v_sites) with ordinality t(s, i)
  where (t.s->>'id')::int = p_site_id;
  if v_idx is null then
    raise exception 'no such camp site';
  end if;
  v_site := v_sites->v_idx;
  v_members := coalesce(v_site->'members', '[]'::jsonb);
  foreach v_id in array v_ids loop
    if not exists (
      select 1 from jsonb_array_elements_text(v_members) m where lower(m) = lower(v_id)
    ) then
      v_members := v_members || to_jsonb(v_id);
      v_changed := true;
    end if;
  end loop;
  if v_changed then
    v_site := jsonb_set(v_site, '{members}', v_members);
    v_sites := jsonb_set(v_sites, array[v_idx::text], v_site);
    update campfire_state
       set version = version + 1,
           data = jsonb_set(data, '{sites}', v_sites)
     where id = 0;
  end if;
end;
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
  v_global_chef boolean := public.campfire_is_chef();
  v_chef boolean;
  v_old   campfire_state%rowtype;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'sign in required';
  end if;
  if p_id is null or p_id < 0 or p_data is null then
    raise exception 'bad request';
  end if;

  -- Site chefs get full chef powers for their own site's row.
  v_chef := v_global_chef or (p_id > 0 and public.campfire_is_site_chef(p_id));

  select * into v_old from campfire_state where id = p_id for update;
  if not found then
    raise exception 'no such camp site';
  end if;
  if v_old.version is distinct from p_expected_version then
    return -1; -- concurrent write: client refetches and retries
  end if;

  if not v_chef then
    if p_id = 0 then
      -- Site chefs may edit the directory, but only their own
      -- site's entry (contacts/chefs), and may not add or renumber
      -- sites.
      if coalesce(v_old.data->'nextSiteId', '0'::jsonb) is distinct from coalesce(p_data->'nextSiteId', '0'::jsonb)
         or exists (
           with olds as (
             select (s->>'id')::int as id, s from jsonb_array_elements(coalesce(v_old.data->'sites', '[]'::jsonb)) s
           ),
           news as (
             select (s->>'id')::int as id, s from jsonb_array_elements(coalesce(p_data->'sites', '[]'::jsonb)) s
           ),
           joined as (
             select coalesce(o.id, n.id) as id, o.s as os, n.s as ns
             from olds o full outer join news n using (id)
           )
           select 1 from joined
           where os is distinct from ns
             and not public.campfire_is_site_chef(id)
         ) then
        raise exception 'only the chef can change the camp site list';
      end if;
      update campfire_state
         set version = v_old.version + 1, data = p_data
       where id = 0;
      return v_old.version + 1;
    end if;
    if (v_old.data->'meals') is distinct from (p_data->'meals') then
      raise exception 'only the chef can change the menu';
    end if;
    if coalesce(v_old.data->'history', '[]'::jsonb) is distinct from coalesce(p_data->'history', '[]'::jsonb)
       or (v_old.data->'day') is distinct from (p_data->'day')
       or coalesce(v_old.data->'cutoffTime', '""'::jsonb) is distinct from coalesce(p_data->'cutoffTime', '""'::jsonb)
       or coalesce(v_old.data->'orderingOverride', 'null'::jsonb) is distinct from coalesce(p_data->'orderingOverride', 'null'::jsonb)
       or coalesce(v_old.data->'dayNote', '""'::jsonb) is distinct from coalesce(p_data->'dayNote', '""'::jsonb) then
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
revoke all on function public.campfire_is_site_chef(integer) from public, anon;
revoke all on function public.campfire_is_member(integer) from public, anon;
revoke all on function public.campfire_join(integer) from public, anon;
revoke all on function public.campfire_seed(integer, jsonb) from public, anon;
revoke all on function public.campfire_write(integer, bigint, jsonb) from public, anon;
grant execute on function public.campfire_is_chef() to authenticated;
grant execute on function public.campfire_seed(integer, jsonb) to authenticated;
grant execute on function public.campfire_write(integer, bigint, jsonb) to authenticated;
grant execute on function public.campfire_is_site_chef(integer) to authenticated;
grant execute on function public.campfire_is_member(integer) to authenticated;
grant execute on function public.campfire_join(integer) to authenticated;

-- ------------------------------------------------------------------
-- Member-only reads (created last: it uses the functions above).
create policy "campfire auth select" on public.campfire_state
  for select to authenticated
  using (id <= 1 or public.campfire_is_chef() or public.campfire_is_member(id));
