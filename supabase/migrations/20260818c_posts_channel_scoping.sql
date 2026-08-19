-- ============================================================
-- Groups Phase 2: posts.channel_id (fixes "every group aliases to
-- one community-wide feed") + RLS
-- ============================================================
-- CommunityChannelScreen currently reads/writes public.posts filtered
-- ONLY by community_id for every non-announcement channel it's opened
-- for -- so "General" and every custom group all show/post into the
-- same feed. This adds the partitioning column plus RLS gating group
-- content behind is_group_member(), matching events (see
-- 20260818d_events_group_extension.sql).
--
-- ON DELETE SET NULL: deleting a group does NOT delete its posts --
-- they fall back to plain (ungrouped) community posts, per the
-- confirmed "detach, don't delete" product decision.
--
-- Verified live against the actual project (2026-08-18) rather than
-- assumed -- exact current policies:
--   posts_delete  (DELETE, authenticated): qual = true
--   posts_insert  (INSERT, authenticated): with_check = true
--   posts_update  (UPDATE, authenticated): qual = true
--   "Posts hidden from blockers and from private non-followers"
--     (SELECT, public): the block/private-follower logic reproduced
--     verbatim below, with the new channel_id condition folded in.
--
-- NOTE (flagged, not fixed here -- out of scope for this migration):
-- posts_insert/update/delete all being unconditionally `true` (no
-- author_id = auth.uid() check at all) is a pre-existing gap unrelated
-- to groups. This migration deliberately does not tighten that --
-- only ANDs in the new channel_id condition -- to avoid an unreviewed
-- security-behavior change riding along with an unrelated feature.
--
-- Postgres OR-combines multiple permissive policies for the same
-- command, so bolting a second, stricter SELECT/INSERT policy on top
-- of an existing permissive one would silently do nothing -- the old
-- one still lets everything through. This migration drops and
-- recreates the existing policies with the new condition folded in,
-- rather than adding new ones alongside them.
--
-- Safe to run multiple times.
-- ============================================================

begin;

alter table public.posts
  add column if not exists channel_id uuid references public.community_channels(id) on delete set null;

create index if not exists idx_posts_channel_id on public.posts (channel_id) where channel_id is not null;

drop policy if exists "Posts hidden from blockers and from private non-followers" on public.posts;
create policy "Posts hidden from blockers and from private non-followers" on public.posts
  for select
  using (
    (author_id = auth.uid())
    or (
      (not exists (
        select 1 from user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = posts.author_id)
           or (b.blocker_id = posts.author_id and b.blocked_id = auth.uid())
      ))
      and (
        (not exists (select 1 from users u where u.id = posts.author_id and u.is_private = true))
        or (exists (
          select 1 from follows f
          where f.follower_id = auth.uid() and f.following_id = posts.author_id and f.status = 'accepted'
        ))
      )
      and (channel_id is null or is_group_member(channel_id))
    )
  );

drop policy if exists "posts_insert" on public.posts;
create policy "posts_insert" on public.posts
  for insert to authenticated
  with check (
    channel_id is null
    or (
      is_group_member(channel_id)
      and exists (
        select 1 from public.community_channels ch
        where ch.id = channel_id and ch.community_id = posts.community_id
      )
    )
  );

commit;
