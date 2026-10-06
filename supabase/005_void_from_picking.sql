-- 005 — let an unplayable pair be voided straight from `picking`
--
-- The bug (found on the emulator, 6 Oct 2026): the host checks the pair the
-- moment both clubs lock in and, if they share no player, calls
--   finish_round(code, null, 'unplayable')
-- while the room is still in `picking` — by design, so nobody watches a
-- countdown for a round that cannot be won. But finish_round's guard only
-- accepted 'answering' and 'countdown', so the call matched no row, returned
-- the room unchanged, and the host retried four times a second forever. The
-- match froze on the pick screen with the timer at 0 and nothing logged.
-- (Real Zaragoza x Nottingham Forest, 0 mutual players, triggered it.)
--
-- The fix widens the guard for exactly that case: `picking` is accepted only
-- with reason 'unplayable' and only once BOTH clubs are in, so it cannot be
-- used to cut a pick window short or score a goal.

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
     and (
           phase in ('answering', 'countdown')
        or (phase = 'picking'
            and p_reason = 'unplayable'
            and p_winner is null
            and host_club_id is not null
            and guest_club_id is not null)
     )
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
