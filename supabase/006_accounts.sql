-- 006 — accounts: anonymous auth users, profiles, and rooms locked to players
--
-- PREREQUISITE: Dashboard -> Authentication -> Sign In / Providers ->
-- "Allow anonymous sign-ins" must be ON. Without it every client sign-in
-- fails and, after this file, nobody can read a room.
--
-- What changes
-- ------------
-- 1. Every install signs in anonymously (supabase_flutter keeps the session,
--    so the auth user is stable for the life of the install). auth.uid() is
--    now the player id everywhere: in profiles, and in rooms.host_id /
--    guest_id.
-- 2. public.profiles holds the identity (username + a 4-character tag that
--    never changes) and the numbers: trophies, coins, match stats.
-- 3. Room RLS is tightened to `auth.uid() in (host_id, guest_id)` — the
--    upgrade friend-match.md describes. The anon role loses its table grants.
--
-- No anti-cheat. Clients are trusted. Column grants decide WHAT a client may
-- write directly (its own username, its own seat's columns); nothing checks
-- whether the values are honest.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  username           text not null,
  -- A–Z and 2–9 without 0/O/1/I, so a tag read aloud or off a screenshot
  -- cannot be mistyped. 32 symbols, 4 places: ~1M tags per username.
  tag                text not null check (tag ~ '^[A-HJ-NP-Z2-9]{4}$'),

  trophies           int  not null default 0  check (trophies >= 0),
  coins              int  not null default 30 check (coins >= 0),

  matches_played     int  not null default 0,
  wins               int  not null default 0,
  current_streak     int  not null default 0,   -- consecutive match wins
  best_streak        int  not null default 0,
  fastest_answer_ms  int,                         -- quickest correct answer

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  -- The rule on the Kullanıcı Adı Oluştur frame (92:190):
  -- "3–16 karakter · harf, rakam ve _". Turkish letters count as letters.
  constraint profiles_username_valid
    check (username ~ '^[A-Za-z0-9_ÇĞİÖŞÜçğıöşü]{3,16}$')
);

-- Usernames need not be unique; the username + tag pair must be. Compared
-- case-insensitively, because people type "yaman#7k2m" when adding a friend.
create unique index if not exists profiles_username_tag_key
  on public.profiles (lower(username), tag);

-- The leaderboard reads this order.
create index if not exists profiles_trophies_idx
  on public.profiles (trophies desc, id);

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- The tag never changes. Enforced here as well as by the column grants below,
-- so even a SECURITY DEFINER function written later cannot quietly re-tag.
create or replace function public.profiles_keep_tag()
returns trigger
language plpgsql
as $$
begin
  if new.tag is distinct from old.tag then
    raise exception 'tag_is_permanent';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_keep_tag on public.profiles;
create trigger profiles_keep_tag
  before update on public.profiles
  for each row execute function public.profiles_keep_tag();

-- ---------------------------------------------------------------------------
-- random_tag / create_profile
-- ---------------------------------------------------------------------------
create or replace function public.random_tag()
returns text
language sql
volatile
as $$
  select string_agg(
           substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                  1 + floor(random() * 32)::int, 1),
           '')
    from generate_series(1, 4);
$$;

-- Creates the caller's profile with a fresh tag, or returns the one that
-- already exists (so a client retrying after a dropped response gets the same
-- profile, not an error). The tag is drawn until the (username, tag) pair is
-- free; the unique index settles any race.
create or replace function public.create_profile(p_username text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_prof public.profiles;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if v_prof.id is not null then
    return v_prof;
  end if;

  for i in 1..30 loop
    begin
      insert into public.profiles (id, username, tag)
      values (v_uid, trim(p_username), public.random_tag())
      returning * into v_prof;
      return v_prof;
    exception when unique_violation then
      -- Either the pair is taken (draw again) or a parallel call from this
      -- same user won the insert (return it).
      select * into v_prof from public.profiles where id = v_uid;
      if v_prof.id is not null then
        return v_prof;
      end if;
    end;
  end loop;
  raise exception 'no_free_tag';
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles RLS + grants
-- ---------------------------------------------------------------------------
-- Anyone signed in may read any profile (leaderboards, friends, opponents).
-- A player may update only their own row, and the column grant limits that
-- to `username`: trophies, coins and stats change only through the SECURITY
-- DEFINER functions in 007.
alter table public.profiles enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- RLS policies do not imply GRANTs (friend-match.md). Without these every
-- direct read fails with 42501.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (username) on public.profiles to authenticated;

grant execute on function public.create_profile(text) to authenticated;

-- ---------------------------------------------------------------------------
-- rooms: carry auth.uid()s, readable and writable only by their two players
-- ---------------------------------------------------------------------------
-- create_room / join_room now take the player id from the session, not from
-- the parameter. The signatures are unchanged so older clients still call
-- them; p_host_id / p_guest_id are ignored.
create or replace function public.create_room(
  p_host_id   uuid,
  p_host_name text
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_code text;
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;
  for i in 1..20 loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    begin
      insert into public.rooms (code, host_id, host_name, host_seen_at)
      values (v_code, v_uid, p_host_name, now())
      returning * into v_room;
      return v_room;
    exception when unique_violation then
    end;
  end loop;
  raise exception 'could not allocate a free room code after 20 attempts';
end;
$$;

create or replace function public.join_room(
  p_code       text,
  p_guest_id   uuid,
  p_guest_name text
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  update public.rooms
     set guest_id = v_uid,
         guest_name = p_guest_name,
         guest_seen_at = now()
   where code = p_code
     and phase = 'lobby'
     and (guest_id is null or guest_id = v_uid)
     and host_id <> v_uid           -- cannot play yourself
  returning * into v_room;

  if v_room.code is null then
    if not exists (select 1 from public.rooms where code = p_code) then
      raise exception 'room_not_found';
    elsif exists (select 1 from public.rooms where code = p_code and phase <> 'lobby') then
      raise exception 'room_in_progress';
    elsif exists (select 1 from public.rooms where code = p_code and host_id = v_uid) then
      raise exception 'own_room';
    else
      raise exception 'room_full';
    end if;
  end if;

  return v_room;
end;
$$;

alter table public.rooms enable row level security;

drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms
  for select to authenticated
  using (auth.uid() in (host_id, guest_id));

-- Rooms are only ever created through create_room (SECURITY DEFINER), so no
-- direct insert is allowed at all any more.
drop policy if exists rooms_insert on public.rooms;

drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms
  for update to authenticated
  using (auth.uid() in (host_id, guest_id))
  with check (auth.uid() in (host_id, guest_id));

revoke all on public.rooms from anon;
revoke insert, delete on public.rooms from authenticated;
grant select, update on public.rooms to authenticated;

grant execute on function public.create_room(uuid,text)    to authenticated;
grant execute on function public.join_room(text,uuid,text) to authenticated;
