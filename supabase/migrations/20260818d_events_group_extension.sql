-- ============================================================
-- Groups Phase 3: events.group_id (Community -> Group -> Event)
-- ============================================================
-- Mirrors the existing nullable events.community_id column/pattern.
-- ON DELETE SET NULL (same "detach, don't delete" reasoning as
-- posts.channel_id in 20260818c).
--
-- Per the confirmed product decision, a group's events are visible
-- only to that group's members (not the whole community) -- same
-- separation as group-scoped posts.
--
-- Verified live against the actual project (2026-08-18) rather than
-- assumed -- exact current policies (both `to authenticated`):
--   events_insert: with_check =
--     (organizer_id = auth.uid())
--     and (community_id is null or is_community_member(community_id))
--   events_select: qual =
--     (community_id is null) or exists (
--       select 1 from communities c where c.id = events.community_id
--       and (c.privacy = 'public' or is_community_member(events.community_id))
--     )
-- Both reproduced verbatim below with the new group_id condition
-- folded in (not added as a second policy -- same OR-combination
-- reasoning as 20260818c).
--
-- Safe to run multiple times.
-- ============================================================

begin;

alter table public.events
  add column if not exists group_id uuid references public.community_channels(id) on delete set null;

create index if not exists idx_events_group_id on public.events (group_id) where group_id is not null;

drop policy if exists "events_insert" on public.events;
create policy "events_insert" on public.events
  for insert to authenticated
  with check (
    (organizer_id = auth.uid())
    and (community_id is null or is_community_member(community_id))
    and (
      group_id is null
      or (
        is_group_member(group_id)
        and exists (
          select 1 from public.community_channels ch
          where ch.id = group_id and ch.community_id = events.community_id
        )
      )
    )
  );

drop policy if exists "events_select" on public.events;
create policy "events_select" on public.events
  for select to authenticated
  using (
    (
      (community_id is null)
      or exists (
        select 1 from communities c
        where c.id = events.community_id
          and (c.privacy = 'public' or is_community_member(events.community_id))
      )
    )
    and (group_id is null or is_group_member(group_id))
  );

commit;
