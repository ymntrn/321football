-- 008 — friends: add by username#tag, request -> accept/decline, remove.
-- Also the two leaderboard helpers (the Arkadaş tab is a friends query).
--
-- Requires 006_accounts.sql.
--
-- One row per pair. `requester` asked, `addressee` was asked; the row is
-- `pending` until the addressee accepts (-> `accepted`) or declines (the row
-- is deleted). Removing a friend deletes the row, whichever side asked. A
-- pair can only ever have one row, in either direction.

create table if not exists public.friendships (
  requester    uuid not null references public.profiles (id) on delete cascade,
  addressee    uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending'
               check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  primary key (requester, addressee),
  check (requester <> addressee)
);

create unique index if not exists friendships_pair_key
  on public.friendships (least(requester, addressee), greatest(requester, addressee));
create index if not exists friendships_addressee_idx
  on public.friendships (addressee);

-- A player reads only the rows they are in. Every write goes through the
-- functions below, so no write grant at all.
alter table public.friendships enable row level security;

drop policy if exists friendships_read on public.friendships;
create policy friendships_read on public.friendships
  for select to authenticated
  using (auth.uid() in (requester, addressee));

revoke all on public.friendships from anon, authenticated;
grant select on public.friendships to authenticated;

-- ---------------------------------------------------------------------------
-- find_player — exact `name#TAG` lookup (the Arkadaş Ekle preview)
-- ---------------------------------------------------------------------------
-- A function rather than a PostgREST filter because `_` is a wildcard in
-- ilike, and usernames are full of underscores.
create or replace function public.find_player(p_username text, p_tag text)
returns public.profiles
language sql
stable
security definer
set search_path = public
as $$
  select * from public.profiles
   where lower(username) = lower(trim(p_username))
     and tag = upper(trim(p_tag))
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- send_friend_request
-- ---------------------------------------------------------------------------
-- Returns what happened: 'sent', 'accepted' (they had already asked you, so
-- this accepts theirs), 'already_sent', or 'already_friends'.
create or replace function public.send_friend_request(p_username text, p_tag text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_other uuid;
  v_row   public.friendships;
begin
  if v_me is null then
    raise exception 'not_signed_in';
  end if;
  select id into v_other from public.find_player(p_username, p_tag);
  if v_other is null then
    raise exception 'player_not_found';
  end if;
  if v_other = v_me then
    raise exception 'cannot_add_self';
  end if;

  select * into v_row from public.friendships
   where (requester = v_me and addressee = v_other)
      or (requester = v_other and addressee = v_me)
   for update;

  if v_row.requester is null then
    insert into public.friendships (requester, addressee)
    values (v_me, v_other)
    on conflict do nothing;
    return 'sent';
  end if;
  if v_row.status = 'accepted' then
    return 'already_friends';
  end if;
  if v_row.requester = v_me then
    return 'already_sent';
  end if;
  -- They asked first: adding them back is a yes.
  update public.friendships
     set status = 'accepted', responded_at = now()
   where requester = v_other and addressee = v_me;
  return 'accepted';
end;
$$;

-- ---------------------------------------------------------------------------
-- respond_friend_request — accept or decline a request made TO me
-- ---------------------------------------------------------------------------
create or replace function public.respond_friend_request(
  p_requester uuid,
  p_accept    boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  if p_accept then
    update public.friendships
       set status = 'accepted', responded_at = now()
     where requester = p_requester
       and addressee = auth.uid()
       and status = 'pending';
  else
    delete from public.friendships
     where requester = p_requester
       and addressee = auth.uid()
       and status = 'pending';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- remove_friend — unfriend, or withdraw a request I sent
-- ---------------------------------------------------------------------------
create or replace function public.remove_friend(p_other uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.friendships
   where (requester = auth.uid() and addressee = p_other)
      or (requester = p_other and addressee = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- my_friends — everyone I have a row with, and which way it points
-- ---------------------------------------------------------------------------
-- status 'accepted' = friend; 'pending' + incoming = they asked me;
-- 'pending' + not incoming = I asked them.
create or replace function public.my_friends()
returns table (
  id        uuid,
  username  text,
  tag       text,
  trophies  int,
  status    text,
  incoming  boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.tag, p.trophies, f.status,
         (f.addressee = auth.uid()) as incoming
    from public.friendships f
    join public.profiles p
      on p.id = case when f.requester = auth.uid() then f.addressee
                     else f.requester end
   where auth.uid() in (f.requester, f.addressee)
   order by f.status desc, p.trophies desc, p.id;
$$;

-- ---------------------------------------------------------------------------
-- Leaderboards
-- ---------------------------------------------------------------------------
-- Global is a plain read of profiles ordered (trophies desc, id) — the
-- client does it directly. my_rank() is this player's position in exactly
-- that order, so the pinned "Kendi Sıran" row agrees with the list when the
-- player is inside the top 100.
create or replace function public.my_rank()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select 1 + count(*)::int
    from public.profiles o, public.profiles me
   where me.id = auth.uid()
     and (o.trophies > me.trophies
          or (o.trophies = me.trophies and o.id < me.id));
$$;

-- The Arkadaş tab: me and my accepted friends, by trophies. No podium and no
-- pinned row — the player is just a highlighted row (game-screens-ui.md).
create or replace function public.friends_leaderboard()
returns setof public.profiles
language sql
stable
security definer
set search_path = public
as $$
  select p.* from public.profiles p
   where p.id = auth.uid()
      or p.id in (
        select case when f.requester = auth.uid() then f.addressee
                    else f.requester end
          from public.friendships f
         where f.status = 'accepted'
           and auth.uid() in (f.requester, f.addressee))
   order by p.trophies desc, p.id;
$$;

revoke execute on function public.find_player(text,text)               from public, anon;
revoke execute on function public.send_friend_request(text,text)       from public, anon;
revoke execute on function public.respond_friend_request(uuid,boolean) from public, anon;
revoke execute on function public.remove_friend(uuid)                  from public, anon;
revoke execute on function public.my_friends()                         from public, anon;
revoke execute on function public.my_rank()                            from public, anon;
revoke execute on function public.friends_leaderboard()                from public, anon;

grant execute on function public.find_player(text,text)               to authenticated;
grant execute on function public.send_friend_request(text,text)       to authenticated;
grant execute on function public.respond_friend_request(uuid,boolean) to authenticated;
grant execute on function public.remove_friend(uuid)                  to authenticated;
grant execute on function public.my_friends()                         to authenticated;
grant execute on function public.my_rank()                            to authenticated;
grant execute on function public.friends_leaderboard()                to authenticated;
