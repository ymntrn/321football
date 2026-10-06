-- 009 — ranked matchmaking ("Hemen Oyna")
--
-- Requires 006 and 007 (rooms.ranked is added in 007).
--
-- The client calls find_match() about once a second while the Maç Aranıyor
-- screen is up. Each call is a heartbeat AND an attempt:
--   * not queued yet  -> joins the queue
--   * someone already paired me -> returns that room (and leaves the queue)
--   * someone waiting within the trophy window -> creates a RANKED room
--     already in `picking` (the same room and engine Friend Match uses,
--     first to 3), marks the other player's queue row with its code, and
--     returns it
--   * nobody yet -> returns null
-- Cancelling calls leave_queue().
--
-- Trophy window (Yaman, 6 Oct 2026): +-100, widened by 100 for every 5 s
-- waited. A pair matches when their difference fits EITHER player's window,
-- so the one who has waited longest is the one who widens the search.
--
-- Every find_match takes one transaction-scoped advisory lock, so two players
-- polling at the same instant cannot each create a room with the other.
-- Matchmaking is a handful of calls a second at most; serialising it costs
-- nothing.

create table if not exists public.match_queue (
  player_id    uuid primary key references public.profiles (id) on delete cascade,
  trophies     int  not null,
  username     text not null,
  -- For the test bot only: the bot cannot drive a match, so it asks to be
  -- the guest. When exactly one side prefers guest, the other hosts;
  -- otherwise the player who finds the match hosts.
  prefer_guest boolean not null default false,
  joined_at    timestamptz not null default now(),
  seen_at      timestamptz not null default now(),
  room_code    text references public.rooms (code) on delete set null
);

-- Functions only. RLS on with no policy, and no grants.
alter table public.match_queue enable row level security;
revoke all on public.match_queue from anon, authenticated;

-- A queued player who stopped polling this long ago has gone.
-- (seconds; the client polls every ~1 s)

create or replace function public.find_match(p_prefer_guest boolean default false)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_me     public.match_queue;
  v_opp    public.match_queue;
  v_room   public.rooms;
  v_code   text;
  v_host   public.match_queue;
  v_guest  public.match_queue;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;
  select * into v_prof from public.profiles where id = v_uid;
  if v_prof.id is null then
    raise exception 'no_profile';
  end if;

  perform pg_advisory_xact_lock(321009);

  -- Somebody already paired me on their call.
  select * into v_me from public.match_queue where player_id = v_uid;
  if v_me.player_id is not null and v_me.room_code is not null then
    delete from public.match_queue where player_id = v_uid;
    select * into v_room from public.rooms where code = v_me.room_code;
    return v_room;
  end if;

  if v_me.player_id is null then
    insert into public.match_queue (player_id, trophies, username, prefer_guest)
    values (v_uid, v_prof.trophies, v_prof.username, p_prefer_guest)
    returning * into v_me;
  else
    update public.match_queue
       set seen_at = now(),
           trophies = v_prof.trophies,
           username = v_prof.username,
           prefer_guest = p_prefer_guest
     where player_id = v_uid
    returning * into v_me;
  end if;

  -- Players who closed the app without cancelling.
  delete from public.match_queue
   where room_code is null
     and seen_at < now() - interval '15 seconds';

  select * into v_opp
    from public.match_queue q
   where q.player_id <> v_uid
     and q.room_code is null
     and abs(q.trophies - v_me.trophies) <= greatest(
           100 + 100 * floor(extract(epoch from now() - v_me.joined_at) / 5),
           100 + 100 * floor(extract(epoch from now() - q.joined_at) / 5))
   order by q.joined_at
   limit 1;

  if v_opp.player_id is null then
    return null;
  end if;

  if v_opp.prefer_guest and not v_me.prefer_guest then
    v_host := v_me;  v_guest := v_opp;
  elsif v_me.prefer_guest and not v_opp.prefer_guest then
    v_host := v_opp; v_guest := v_me;
  else
    v_host := v_me;  v_guest := v_opp;
  end if;

  for i in 1..20 loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    begin
      insert into public.rooms (code, host_id, host_name, guest_id, guest_name,
                                host_seen_at, guest_seen_at, ranked)
      values (v_code, v_host.player_id, v_host.username,
              v_guest.player_id, v_guest.username, now(), now(), true);
      exit;
    exception when unique_violation then
      v_code := null;
    end;
  end loop;
  if v_code is null then
    raise exception 'could not allocate a free room code after 20 attempts';
  end if;

  -- Straight into round 1. The other player only learns of the room on
  -- their next poll (up to ~1 s), so the pick window gets 2 s of slack.
  perform public.start_match(v_code);
  update public.rooms
     set pick_deadline = pick_deadline + interval '2 seconds'
   where code = v_code;

  update public.match_queue set room_code = v_code
   where player_id = v_opp.player_id;
  delete from public.match_queue where player_id = v_uid;

  select * into v_room from public.rooms where code = v_code;
  return v_room;
end;
$$;

-- Cancel. If a match was made in the instant before the cancel landed, it
-- is too late to back out cleanly: the room is returned and the client
-- enters it (walking out of a made match would forfeit it).
create or replace function public.leave_queue()
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   public.match_queue;
  v_room public.rooms;
begin
  perform pg_advisory_xact_lock(321009);
  delete from public.match_queue where player_id = auth.uid()
  returning * into v_me;
  if v_me.room_code is not null then
    select * into v_room from public.rooms where code = v_me.room_code;
  end if;
  return v_room;
end;
$$;

revoke execute on function public.find_match(boolean) from public, anon;
revoke execute on function public.leave_queue()       from public, anon;
grant execute on function public.find_match(boolean) to authenticated;
grant execute on function public.leave_queue()       to authenticated;
