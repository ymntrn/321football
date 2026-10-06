-- Patch 004 — forfeit, rematch, reconnect, cleanup
--
-- What this fixes, in order of how much it hurts:
--
-- 1. forfeit() was dead code. Every client writes a heartbeat every five
--    seconds and nothing ever read one, so a player who closed the app or
--    lost signal simply froze the other player's match. Three rooms sat in
--    'picking' for up to 95 minutes during one afternoon of testing.
-- 2. A finished room was a dead end — start_match is guarded on
--    phase = 'lobby', so two friends wanting a second game had to create a
--    new room and re-share the code.
-- 3. Nothing reconnected. Killing the app mid-match lost the match, which
--    matters far more once (1) means the opponent actually wins it.
-- 4. purge_stale_rooms() existed and was never called.

-- ---------------------------------------------------------------------------
-- claim_forfeit — "my opponent has gone quiet, give me the match"
-- ---------------------------------------------------------------------------
-- THE STALENESS CHECK IS SERVER-SIDE ON PURPOSE, and it is not anti-cheat.
--
-- A client can only observe that updates have stopped arriving. It cannot
-- tell the difference between "the opponent is gone" and "MY connection
-- dropped" — and in the second case the opponent is alive and playing. If the
-- claim were honoured on the claimant's say-so, a brief blip on the losing
-- player's wifi would silently hand them the match. Checking the other seat's
-- own heartbeat against now() settles it with the one clock both players
-- agree on.
create or replace function public.claim_forfeit(
  p_code      text,
  p_claimant  text,                -- 'host' | 'guest'
  p_silence   int default 20       -- seconds of silence that count as gone
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms;
  v_other_seen timestamptz;
  v_loser text;
begin
  select * into v_room from public.rooms where code = p_code;
  if v_room.code is null then
    raise exception 'room_not_found';
  end if;
  if v_room.phase = 'match_over' then
    return v_room;                  -- already decided; nothing to claim
  end if;

  v_loser := case when p_claimant = 'host' then 'guest' else 'host' end;
  v_other_seen := case when v_loser = 'host'
                       then coalesce(v_room.host_seen_at, v_room.created_at)
                       else coalesce(v_room.guest_seen_at, v_room.created_at)
                  end;

  -- The opponent is still checking in, so whatever the claimant is seeing is
  -- on their own side of the wire. Hand back the row unchanged.
  if now() - v_other_seen < make_interval(secs => p_silence) then
    return v_room;
  end if;

  update public.rooms
     set phase        = 'match_over',
         winner       = p_claimant,
         ended_reason = 'forfeit_' || v_loser
   where code = p_code
     and phase <> 'match_over'
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- leave_match — "I am going, award it to the other one"
-- ---------------------------------------------------------------------------
-- No staleness check here: the player is telling us directly, which is the
-- one case where a client genuinely knows more than the server does.
create or replace function public.leave_match(p_code text, p_seat text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase        = 'match_over',
         winner       = case when p_seat = 'host' then 'guest' else 'host' end,
         ended_reason = 'forfeit_' || p_seat
   where code = p_code
     and phase <> 'match_over'
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- rematch — same two players, same room, scores back to nil
-- ---------------------------------------------------------------------------
-- Returns the room to 'lobby' rather than straight into a round, so the host
-- still presses Başlat and neither player is dropped into a pick phase they
-- were not looking at.
create or replace function public.rematch(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase            = 'lobby',
         round            = 0,
         host_score       = 0,
         guest_score      = 0,
         host_club_id     = null, host_club_name   = null,
         guest_club_id    = null, guest_club_name  = null,
         host_answer      = null, host_elapsed_ms  = null,
         guest_answer     = null, guest_elapsed_ms = null,
         round_winner     = null, round_reason     = null,
         winner           = null, ended_reason     = null,
         pick_deadline    = null, unlock_at        = null,
         answer_deadline  = null
   where code = p_code
     and phase = 'match_over'
     and guest_id is not null       -- both seats still filled
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- active_room_for — reconnect after the app was killed
-- ---------------------------------------------------------------------------
-- The player id lives in the device's own storage and survives a restart, so
-- getting back into a match is a lookup rather than anything clever. Bounded
-- to the last hour: a room older than that is abandoned, not interrupted.
create or replace function public.active_room_for(p_player_id uuid)
returns public.rooms
language sql
security definer
set search_path = public
as $$
  select * from public.rooms
   where (host_id = p_player_id or guest_id = p_player_id)
     and phase <> 'match_over'
     and created_at > now() - interval '1 hour'
   order by updated_at desc
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- abandon_stale_matches — close the ones nobody came back to
-- ---------------------------------------------------------------------------
-- Distinct from deleting them. A match both players walked away from should
-- read as finished rather than sit in 'picking' forever, and closing it frees
-- both players' active_room_for lookups so a stale row cannot drag somebody
-- back into a match that ended an hour ago.
create or replace function public.abandon_stale_matches(p_silence int default 600)
returns int
language sql
security definer
set search_path = public
as $$
  with closed as (
    update public.rooms
       set phase = 'match_over',
           ended_reason = 'abandoned'
     where phase not in ('lobby', 'match_over')
       and now() - greatest(coalesce(host_seen_at, created_at),
                            coalesce(guest_seen_at, created_at))
           > make_interval(secs => p_silence)
    returning 1
  )
  select count(*)::int from closed;
$$;

grant execute on function public.claim_forfeit(text,text,int)  to anon, authenticated;
grant execute on function public.leave_match(text,text)        to anon, authenticated;
grant execute on function public.rematch(text)                 to anon, authenticated;
grant execute on function public.active_room_for(uuid)         to anon, authenticated;
grant execute on function public.abandon_stale_matches(int)    to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Housekeeping on a schedule
-- ---------------------------------------------------------------------------
-- pg_cron 1.6.4 is available on this project. If creating the extension is
-- refused, enable it once in Dashboard -> Database -> Extensions and re-run
-- this file; everything above will already have applied.
create extension if not exists pg_cron;

select cron.unschedule(jobid)
  from cron.job
 where jobname in ('321-purge-rooms', '321-abandon-matches');

select cron.schedule(
  '321-abandon-matches', '*/15 * * * *',
  $$select public.abandon_stale_matches(600)$$
);

select cron.schedule(
  '321-purge-rooms', '17 4 * * *',
  $$select public.purge_stale_rooms()$$
);

-- Close out the rooms already stranded by the missing forfeit path.
select public.abandon_stale_matches(600) as closed_now;
