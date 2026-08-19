-- ============================================================
-- Groups Phase 1: group_members table + is_group_member() helper
-- ============================================================
-- Groups already exist as `community_channels` (the "Manage Groups" UI
-- already creates/lists/deletes rows there). This adds real per-group
-- membership, mirroring community_members' shape and RLS conventions
-- exactly (see 20260816_communities_rls_and_announcements_fix.sql for
-- the pattern being followed, and is_community_member() for the helper
-- function pattern). Role model is intentionally simple for this pass:
-- 'member' | 'leader' (no separate group-admin tier); a community
-- admin/moderator can always manage any group's membership too (staff
-- override).
--
-- Verified live against the actual project (2026-08-18) rather than
-- assumed:
--   - community_channels columns: id, community_id, name, description,
--     channel_type, is_default, created_by, created_at -- matches
--     CommunityChannelModel exactly.
--   - community_members already has PRIMARY KEY (community_id, user_id)
--     -- no defensive constraint needed here.
--   - is_community_member(p_community_id) exists; mirrored below.
--
-- Safe to run multiple times.
-- ============================================================

begin;

create table if not exists public.group_members (
  group_id   uuid not null references public.community_channels(id) on delete cascade,
  user_id    uuid not null references public.users(id) on delete cascade,
  role       text not null default 'member' check (role in ('member', 'leader')),
  status     text not null default 'approved' check (status in ('pending', 'approved', 'banned')),
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);

comment on table public.group_members is
  'Per-group membership, mirroring community_members. Populated by joinGroup() (self, open join) and _enrollInDefaultGroups() (auto-enrollment into a community''s default General/Announcements groups whenever someone joins that community).';

create index if not exists idx_group_members_user_id on public.group_members (user_id);

alter table public.group_members enable row level security;

drop policy if exists "group_members_select" on public.group_members;
create policy "group_members_select" on public.group_members
  for select to authenticated using (true);

-- INSERT: self as 'member' only, OR a leader/community-admin-moderator
-- adding someone else as 'member'. Nobody can insert role='leader' --
-- promotion is an UPDATE (below), auditable/reversible like community
-- admin/moderator promotion already is.
drop policy if exists "group_members_insert" on public.group_members;
create policy "group_members_insert" on public.group_members
  for insert to authenticated
  with check (
    role = 'member'
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.group_members gm
        where gm.group_id = group_members.group_id
          and gm.user_id = auth.uid() and gm.role = 'leader' and gm.status = 'approved'
      )
      or exists (
        select 1 from public.community_channels ch
        join public.community_members cm on cm.community_id = ch.community_id
        where ch.id = group_members.group_id
          and cm.user_id = auth.uid() and cm.role in ('admin', 'moderator') and cm.status = 'approved'
      )
    )
  );

drop policy if exists "group_members_update" on public.group_members;
create policy "group_members_update" on public.group_members
  for update to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = group_members.group_id
        and gm.user_id = auth.uid() and gm.role = 'leader' and gm.status = 'approved'
    )
    or exists (
      select 1 from public.community_channels ch
      join public.community_members cm on cm.community_id = ch.community_id
      where ch.id = group_members.group_id
        and cm.user_id = auth.uid() and cm.role in ('admin', 'moderator') and cm.status = 'approved'
    )
  );

drop policy if exists "group_members_delete" on public.group_members;
create policy "group_members_delete" on public.group_members
  for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = group_members.group_id
        and gm.user_id = auth.uid() and gm.role = 'leader' and gm.status = 'approved'
    )
    or exists (
      select 1 from public.community_channels ch
      join public.community_members cm on cm.community_id = ch.community_id
      where ch.id = group_members.group_id
        and cm.user_id = auth.uid() and cm.role in ('admin', 'moderator') and cm.status = 'approved'
    )
  );

create or replace function public.is_group_member(p_group_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from group_members
    where group_id = p_group_id and user_id = auth.uid() and status = 'approved'
  );
$function$;

-- ── Backfill: auto-enroll every existing approved community member
--    into their community's *default* groups (Announcements + General,
--    seeded by seedDefaultChannels()). Without this, the moment
--    posts/events RLS starts requiring is_group_member(), every
--    existing member instantly loses posting access to "General" --
--    a real regression, not hypothetical. Going forward,
--    joinCommunity()/approveRequest()/addMembers() also perform this
--    enrollment via _enrollInDefaultGroups() -- see
--    communities_repository.dart.
insert into public.group_members (group_id, user_id, role, status, joined_at)
select ch.id, cm.user_id, 'member', 'approved', now()
from public.community_channels ch
join public.community_members cm on cm.community_id = ch.community_id
where ch.is_default = true and cm.status = 'approved'
on conflict (group_id, user_id) do nothing;

commit;
