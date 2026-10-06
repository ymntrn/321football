-- 007 — match results: stats for every match, trophies and coins for ranked
--
-- Requires 006_accounts.sql.
--
-- record_match_result(code) is IDEMPOTENT: the first call on a finished
-- match writes both players' stats (and, for a ranked room, trophies and
-- coins) and stamps rooms.result_recorded_at; every later call returns the
-- row unchanged. The host calls it when the match ends — and so does the
-- guest, because a host who walked out (forfeit) is not there to call it.
-- Two calls racing are serialised by the row lock.
--
-- Economy (Yaman, 6 Oct 2026):
--   ranked win   +30 trophies, +10 coins
--   ranked loss  -20 trophies (never below 0), +2 coins
--   Friend Match counts toward stats only: never trophies, never coins.
--
-- No anti-cheat. The function trusts whatever the room row says.

-- ---------------------------------------------------------------------------
-- rooms: ranked flag, per-match bests, the recorded result
-- ---------------------------------------------------------------------------
-- `ranked` is added here rather than in 009 because record_match_result
-- needs it; 009 is what sets it.
alter table public.rooms add column if not exists ranked             boolean not null default false;
alter table public.rooms add column if not exists host_best_ms       int;
alter table public.rooms add column if not exists guest_best_ms      int;
alter table public.rooms add column if not exists result_recorded_at timestamptz;
alter table public.rooms add column if not exists host_trophy_delta  int;
alter table public.rooms add column if not exists guest_trophy_delta int;
alter table public.rooms add column if not exists host_coin_delta    int;
alter table public.rooms add column if not exists guest_coin_delta   int;

-- next_round wipes the elapsed columns every round, so the fastest correct
-- answer of the MATCH has to be kept as the answers arrive. A trigger rather
-- than an edit to finish_round / next_round: those live in earlier
-- migrations, and this way they stay untouched. A rematch (back to `lobby`)
-- clears the bests and the recorded result, so the next match in the same
-- room is recorded afresh.
create or replace function public.rooms_track_match()
returns trigger
language plpgsql
as $$
begin
  if new.phase = 'lobby' and old.phase is distinct from 'lobby' then
    new.host_best_ms       := null;
    new.guest_best_ms      := null;
    new.result_recorded_at := null;
    new.host_trophy_delta  := null;
    new.guest_trophy_delta := null;
    new.host_coin_delta    := null;
    new.guest_coin_delta   := null;
    return new;
  end if;
  -- least() ignores nulls, so the first answer simply becomes the best.
  if new.host_elapsed_ms is not null
     and new.host_elapsed_ms is distinct from old.host_elapsed_ms then
    new.host_best_ms := least(old.host_best_ms, new.host_elapsed_ms);
  end if;
  if new.guest_elapsed_ms is not null
     and new.guest_elapsed_ms is distinct from old.guest_elapsed_ms then
    new.guest_best_ms := least(old.guest_best_ms, new.guest_elapsed_ms);
  end if;
  return new;
end;
$$;

drop trigger if exists rooms_track_match on public.rooms;
create trigger rooms_track_match
  before update on public.rooms
  for each row execute function public.rooms_track_match();

-- ---------------------------------------------------------------------------
-- record_match_result
-- ---------------------------------------------------------------------------
create or replace function public.record_match_result(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room        public.rooms;
  v_winner_id   uuid;
  v_loser_id    uuid;
  v_winner_best int;
  v_loser_best  int;
  v_loser_troph int;
  v_w_trophy    int := 0;
  v_l_trophy    int := 0;
  v_w_coin      int := 0;
  v_l_coin      int := 0;
begin
  select * into v_room from public.rooms where code = p_code for update;
  if v_room.code is null then
    raise exception 'room_not_found';
  end if;

  -- Not finished yet, or already recorded: nothing to do.
  if v_room.phase <> 'match_over' or v_room.result_recorded_at is not null then
    return v_room;
  end if;

  -- An abandoned match (no winner) or a room that never had a guest counts
  -- for nobody. Stamp it so later calls stay no-ops.
  if v_room.winner is null or v_room.guest_id is null then
    update public.rooms set result_recorded_at = now()
     where code = p_code
    returning * into v_room;
    return v_room;
  end if;

  if v_room.winner = 'host' then
    v_winner_id := v_room.host_id;   v_loser_id := v_room.guest_id;
    v_winner_best := v_room.host_best_ms; v_loser_best := v_room.guest_best_ms;
  else
    v_winner_id := v_room.guest_id;  v_loser_id := v_room.host_id;
    v_winner_best := v_room.guest_best_ms; v_loser_best := v_room.host_best_ms;
  end if;

  if v_room.ranked then
    select trophies into v_loser_troph
      from public.profiles where id = v_loser_id for update;
    v_w_trophy := 30;
    v_l_trophy := -least(20, coalesce(v_loser_troph, 0));
    v_w_coin   := 10;
    v_l_coin   := 2;
  end if;

  update public.profiles
     set matches_played    = matches_played + 1,
         wins              = wins + 1,
         current_streak    = current_streak + 1,
         best_streak       = greatest(best_streak, current_streak + 1),
         fastest_answer_ms = least(fastest_answer_ms, v_winner_best),
         trophies          = trophies + v_w_trophy,
         coins             = coins + v_w_coin
   where id = v_winner_id;

  update public.profiles
     set matches_played    = matches_played + 1,
         current_streak    = 0,
         fastest_answer_ms = least(fastest_answer_ms, v_loser_best),
         trophies          = greatest(trophies + v_l_trophy, 0),
         coins             = coins + v_l_coin
   where id = v_loser_id;

  update public.rooms
     set result_recorded_at = now(),
         host_trophy_delta  = case when v_room.winner = 'host'  then v_w_trophy else v_l_trophy end,
         guest_trophy_delta = case when v_room.winner = 'guest' then v_w_trophy else v_l_trophy end,
         host_coin_delta    = case when v_room.winner = 'host'  then v_w_coin   else v_l_coin   end,
         guest_coin_delta   = case when v_room.winner = 'guest' then v_w_coin   else v_l_coin   end
   where code = p_code
  returning * into v_room;

  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- spend_coins — Practice's "3 ALTIN HARCA"
-- ---------------------------------------------------------------------------
-- Returns the new balance; refuses (and changes nothing) when it is short.
create or replace function public.spend_coins(p_amount int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_balance int;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  update public.profiles
     set coins = coins - p_amount
   where id = auth.uid()
     and p_amount > 0
     and coins >= p_amount
  returning coins into v_balance;
  if v_balance is null then
    raise exception 'insufficient_coins';
  end if;
  return v_balance;
end;
$$;

revoke execute on function public.record_match_result(text) from public, anon;
revoke execute on function public.spend_coins(int) from public, anon;
grant execute on function public.record_match_result(text) to authenticated;
grant execute on function public.spend_coins(int)          to authenticated;
