-- Patch 002 — table privileges for the anon role
--
-- schema.sql enabled RLS and wrote policies, which is only half the job.
-- Postgres checks GRANTs first and RLS second: with no grant, every direct
-- read or write of public.rooms fails with
--     42501  permission denied for table rooms
-- regardless of how permissive the policies are. Supabase grants these
-- automatically for tables created through the dashboard's table editor; a
-- table created from raw SQL in the editor does not get them.
--
-- The RPCs (create_room, join_room) kept working throughout because they are
-- SECURITY DEFINER and run as their owner, which is exactly why this did not
-- show up until something touched the table directly.
--
-- DELETE is deliberately not granted. Rooms are removed only by
-- purge_stale_rooms(), which is SECURITY DEFINER, so a client cannot drop a
-- match in progress even by accident.

grant select, insert, update on public.rooms to anon, authenticated;

-- Verify: this should list select/insert/update for anon and authenticated,
-- and no delete.
select grantee, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public'
   and table_name = 'rooms'
   and grantee in ('anon', 'authenticated')
 order by grantee, privilege_type;
