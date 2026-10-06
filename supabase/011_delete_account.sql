-- 011 — in-app account deletion ("Hesabımı sil", Destek & İletişim)
--
-- Requires 006 (profiles), 008 (friendships), 009 (match_queue) and
-- 010 (coin_doubles).
--
-- Google Play requires apps with accounts to let players delete them from
-- inside the app. delete_my_account() removes, for the CALLER only:
--   * their friendships and friend requests, both directions (008)
--   * their matchmaking queue entry (009)
--   * their 2X Altın records (010)
--   * their profile: username, tag, stats, trophies, coins (006)
--   * their auth user — the anonymous id, and a linked Google identity
-- Each table is cleared explicitly rather than trusting the ON DELETE
-- CASCADE chain, so the function says exactly what it removes.
--
-- Rooms are NOT deleted: an in-progress room belongs to the opponent too,
-- and every room is purged by pg_cron within a day (004), which is what the
-- privacy policy says. The deleted player's name stays on such a room until
-- then; nothing joins back to the gone profile.
--
-- Returns true when an account was deleted, false when there was nothing
-- left to delete (a repeat call with the old, still-unexpired JWT). The
-- client signs out afterwards either way.

create or replace function public.delete_my_account()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_n   int;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  delete from public.friendships
   where requester = v_uid or addressee = v_uid;
  delete from public.match_queue where player_id = v_uid;
  delete from public.coin_doubles where player_id = v_uid;
  delete from public.profiles where id = v_uid;
  delete from auth.users where id = v_uid;
  get diagnostics v_n = row_count;

  return v_n > 0;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
