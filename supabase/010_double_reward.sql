-- 010 — "2X Altın": a rewarded ad doubles a ranked win's coins, once
--
-- Requires 007_results.sql (the recorded result and the coin deltas).
--
-- double_match_coins(code) is IDEMPOTENT. It pays the caller the ranked
-- win's coin reward a second time — only when:
--   * the caller is one of the room's two players,
--   * the room is ranked,
--   * the match is over AND record_match_result has run (the win is paid),
--   * the caller WON it.
-- The first call that passes those checks adds the coins and returns the
-- room with the caller's coin delta doubled (+10 -> +20), so the result
-- screen shows the new amount. Every later call for the same match returns
-- the room unchanged.
--
-- "Once" is held in its own table rather than a flag on `rooms`: since 006
-- the two players may UPDATE any column of their room, so a flag there could
-- simply be cleared again. coin_doubles has no client grants at all; only
-- this function writes it. (That is not anti-cheat — nothing here checks
-- whether an ad was really watched, by decision. It is just what "once"
-- means.)
--
-- The bonus is the decided ranked-win reward, 10, not whatever the room's
-- coin delta column says (clients can write that column). If the economy in
-- 007 changes, change v_win_coins here too.

-- ---------------------------------------------------------------------------
-- coin_doubles — one row per doubled match
-- ---------------------------------------------------------------------------
-- Keyed by the match, not the room: a room's result_recorded_at is reset by
-- a rematch, so each match recorded in a room is its own key. Rooms are
-- purged nightly; these rows are tiny and outlive them on purpose.
create table if not exists public.coin_doubles (
  room_code          text        not null,
  player_id          uuid        not null references auth.users(id) on delete cascade,
  match_recorded_at  timestamptz not null,
  coins              int         not null,
  doubled_at         timestamptz not null default now(),
  primary key (room_code, player_id, match_recorded_at)
);

-- Functions only: RLS on with no policy, and no table grants.
alter table public.coin_doubles enable row level security;
revoke all on public.coin_doubles from anon, authenticated;

-- ---------------------------------------------------------------------------
-- double_match_coins
-- ---------------------------------------------------------------------------
create or replace function public.double_match_coins(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms;
  v_seat      text;
  v_win_coins constant int := 10;   -- the ranked win reward (007)
  v_inserted  int;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  select * into v_room from public.rooms where code = p_code for update;
  if v_room.code is null
     or (v_room.host_id is distinct from v_uid
         and v_room.guest_id is distinct from v_uid) then
    raise exception 'room_not_found';
  end if;
  v_seat := case when v_room.host_id = v_uid then 'host' else 'guest' end;

  if not v_room.ranked then
    raise exception 'not_ranked';
  end if;
  if v_room.phase <> 'match_over' or v_room.result_recorded_at is null then
    raise exception 'result_not_recorded';
  end if;
  if v_room.winner is distinct from v_seat then
    raise exception 'not_a_win';
  end if;

  insert into public.coin_doubles (room_code, player_id, match_recorded_at, coins)
  values (p_code, v_uid, v_room.result_recorded_at, v_win_coins)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;

  -- Already doubled: the idempotent no-op.
  if v_inserted = 0 then
    return v_room;
  end if;

  update public.profiles
     set coins = coins + v_win_coins
   where id = v_uid;

  update public.rooms
     set host_coin_delta  = case when v_seat = 'host'
                                 then coalesce(host_coin_delta, 0) + v_win_coins
                                 else host_coin_delta end,
         guest_coin_delta = case when v_seat = 'guest'
                                 then coalesce(guest_coin_delta, 0) + v_win_coins
                                 else guest_coin_delta end
   where code = p_code
  returning * into v_room;

  return v_room;
end;
$$;

revoke execute on function public.double_match_coins(text) from public, anon;
grant execute on function public.double_match_coins(text) to authenticated;
