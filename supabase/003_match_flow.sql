-- Patch 003 — the match state transitions
--
-- WHY THESE ARE FUNCTIONS AND NOT PLAIN UPDATES
--
-- Every phase change that sets a deadline has to stamp it with the SERVER's
-- clock. PostgREST cannot express `now() + interval` in a PATCH body, so a
-- client doing it directly would have to compute the instant from its own
-- clock — which is exactly the drift the whole design exists to avoid. These
-- functions let Postgres evaluate now() itself, so both phones read the same
-- instant and merely have to work out where it falls on their own clocks.
--
-- WHO CALLS THEM
--
-- The HOST advances the match; the guest only ever writes its own columns
-- (its club pick, its answer, its heartbeat). That rule is what keeps the two
-- clients from racing to write the same transition, and it costs nothing,
-- because a host that disappears forfeits the match anyway — there is no need
-- to migrate the role.
--
-- EVERY FUNCTION IS GUARDED AND IDEMPOTENT
--
-- Each UPDATE carries a `where phase = ...` guard, so calling it twice does
-- nothing the second time rather than restarting a clock mid-round. When the
-- guard does not match, the function returns the row AS IT STANDS instead of
-- null, so a caller can always just take the returned row as current truth.

-- ---------------------------------------------------------------------------
-- start_match — lobby -> picking, round 1
-- ---------------------------------------------------------------------------
create or replace function public.start_match(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase           = 'picking',
         round           = 1,
         host_score      = 0,
         guest_score     = 0,
         host_club_id    = null, host_club_name  = null,
         guest_club_id   = null, guest_club_name = null,
         host_answer     = null, host_elapsed_ms = null,
         guest_answer    = null, guest_elapsed_ms = null,
         round_winner    = null, round_reason    = null,
         winner          = null, ended_reason    = null,
         unlock_at       = null, answer_deadline = null,
         pick_deadline   = now() + pick_seconds * interval '1 second'
   where code = p_code
     and phase = 'lobby'
     and guest_id is not null      -- never start a match with one player
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- begin_countdown — picking -> countdown, once BOTH clubs are in
-- ---------------------------------------------------------------------------
-- unlock_at is when the 3-2-1 finishes and typing opens. answer_deadline is
-- unlock_at plus the answer window, computed from the same now() so the two
-- cannot drift apart by a round trip.
create or replace function public.begin_countdown(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase           = 'countdown',
         unlock_at       = now() + countdown_seconds * interval '1 second',
         answer_deadline = now()
                           + (countdown_seconds + answer_seconds)
                             * interval '1 second'
   where code = p_code
     and phase = 'picking'
     and host_club_id is not null
     and guest_club_id is not null
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- open_answers — countdown -> answering
-- ---------------------------------------------------------------------------
-- Purely a marker: the deadlines were already fixed by begin_countdown, and
-- each client opens its own input when its local clock reaches unlock_at.
-- This exists so a client joining late, or recovering from a reconnect, can
-- read the phase and know where it is without doing time arithmetic.
create or replace function public.open_answers(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms set phase = 'answering'
   where code = p_code and phase = 'countdown'
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- finish_round — answering -> round_over, applying the goal
-- ---------------------------------------------------------------------------
-- The caller passes the verdict it computed from the two elapsed times. Both
-- clients compute the same verdict from the same row, but only the host
-- writes it.
--
-- p_winner: 'host' | 'guest' | null (a void round scores nothing)
-- p_reason: 'correct' | 'no_answer' | 'unplayable'
--
-- The match ends here too, so the target-goal check lives in one place rather
-- than being repeated by whoever happens to write next.
create or replace function public.finish_round(
  p_code   text,
  p_winner text,
  p_reason text
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase        = 'round_over',
         round_winner = p_winner,
         round_reason = p_reason,
         host_score   = host_score  + case when p_winner = 'host'  then 1 else 0 end,
         guest_score  = guest_score + case when p_winner = 'guest' then 1 else 0 end
   where code = p_code
     and phase in ('answering', 'countdown')
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
    return v_room;
  end if;

  if v_room.host_score >= v_room.target_goals
     or v_room.guest_score >= v_room.target_goals then
    update public.rooms
       set phase        = 'match_over',
           winner       = case when host_score >= target_goals
                               then 'host' else 'guest' end,
           ended_reason = 'goals'
     where code = p_code
    returning * into v_room;
  end if;

  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- next_round — round_over -> picking, one round on
-- ---------------------------------------------------------------------------
-- A VOIDED round does not advance the round number: the decision of
-- 13 Sep 2026 is that an unplayable pair is replayed, not counted, so the
-- players see the same round number again with fresh clubs.
create or replace function public.next_round(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase            = 'picking',
         round            = round + case when round_reason = 'unplayable'
                                         then 0 else 1 end,
         host_club_id     = null, host_club_name   = null,
         guest_club_id    = null, guest_club_name  = null,
         host_answer      = null, host_elapsed_ms  = null,
         guest_answer     = null, guest_elapsed_ms = null,
         round_winner     = null, round_reason     = null,
         unlock_at        = null, answer_deadline  = null,
         pick_deadline    = now() + pick_seconds * interval '1 second'
   where code = p_code
     and phase = 'round_over'
  returning * into v_room;

  if v_room.code is null then
    select * into v_room from public.rooms where code = p_code;
  end if;
  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- forfeit — someone left, the other player takes the match
-- ---------------------------------------------------------------------------
-- The decision (13 Sep 2026) is immediate forfeit: no grace period, no seat
-- held open. p_loser is the seat that vanished.
create or replace function public.forfeit(p_code text, p_loser text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare v_room public.rooms;
begin
  update public.rooms
     set phase        = 'match_over',
         winner       = case when p_loser = 'host' then 'guest' else 'host' end,
         ended_reason = 'forfeit_' || p_loser
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
-- touch_seen — liveness, stamped by the server
-- ---------------------------------------------------------------------------
-- Stamped server-side so the two heartbeats are comparable to each other and
-- to now(). A client writing its own clock here would make a phone whose time
-- is ten minutes slow look permanently dead.
create or replace function public.touch_seen(p_code text, p_seat text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.rooms
     set host_seen_at  = case when p_seat = 'host'  then now() else host_seen_at  end,
         guest_seen_at = case when p_seat = 'guest' then now() else guest_seen_at end
   where code = p_code;
$$;

grant execute on function public.start_match(text)              to anon, authenticated;
grant execute on function public.begin_countdown(text)          to anon, authenticated;
grant execute on function public.open_answers(text)             to anon, authenticated;
grant execute on function public.finish_round(text,text,text)   to anon, authenticated;
grant execute on function public.next_round(text)               to anon, authenticated;
grant execute on function public.forfeit(text,text)             to anon, authenticated;
grant execute on function public.touch_seen(text,text)          to anon, authenticated;
