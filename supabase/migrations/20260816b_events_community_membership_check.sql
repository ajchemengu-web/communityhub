-- ============================================================
-- Require community membership to attach an event to a community
-- ============================================================
-- events_insert previously only checked `organizer_id = auth.uid()` --
-- nothing stopped an authenticated user from creating an event with
-- community_id set to ANY community, including ones they don't belong
-- to. That was a low-severity gap while the app-side UI never sent a
-- community_id at all (see create_event_screen.dart's former
-- `communityId: null // TODO: community selector`), but now that the
-- UI offers a real community picker, the same restriction needs to
-- exist at the database level too -- the UI only ever offers
-- communities the signed-in user already belongs to (via
-- CommunitiesRepository.fetchMyCommunities()), but that's a client-side
-- convenience, not a security boundary; someone could otherwise still
-- call the API directly with any community_id.
--
-- Personal (non-community) events are unaffected -- community_id IS
-- NULL is still always allowed.
--
-- Safe to run multiple times.
-- ============================================================

begin;

drop policy if exists "events_insert" on public.events;
create policy "events_insert" on public.events
  for insert
  to authenticated
  with check (
    organizer_id = auth.uid()
    and (
      community_id is null
      or is_community_member(community_id)
    )
  );

commit;
