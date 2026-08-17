-- The community_members INSERT policy from
-- 20260816_communities_rls_and_announcements_fix.sql closed a real
-- privilege-escalation hole (anyone could insert a row granting
-- themselves 'admin' in any community) by requiring `user_id =
-- auth.uid()` on every insert. That migration's own comment says this
-- should still allow "bulk add-members" to keep working, but the
-- actual policy never accounted for it: CommunitiesRepository.
-- addMembers() -- used by the "Add members" screen -- inserts rows
-- with `user_id` set to the PERSON BEING ADDED, not the admin
-- performing the action, so `user_id = auth.uid()` is false for every
-- one of those rows. Confirmed live: an admin trying to add a member
-- got "new row violates row-level security policy for table
-- community_members" (42501).
--
-- This adds the missing case as an OR branch, alongside the existing
-- self-service paths (self-join as 'member', creator claiming the
-- one-time initial 'admin' row) -- it does not loosen either of those.
-- The new branch only ever allows role='member' + status='approved'
-- rows for someone ELSE, and only when the inserting user is already
-- an approved admin or moderator of that same community -- it can
-- never be used to grant anyone (including the actor) an elevated
-- role, which is what the original hole was about.
drop policy if exists "members_insert" on public.community_members;
create policy "members_insert" on public.community_members
  for insert
  to authenticated
  with check (
    (
      user_id = auth.uid()
      and (
        role = 'member'
        or (
          role = 'admin'
          and exists (
            select 1 from public.communities c
            where c.id = community_id
              and c.creator_id = auth.uid()
          )
        )
      )
    )
    or (
      role = 'member'
      and status = 'approved'
      and exists (
        select 1 from public.community_members cm
        where cm.community_id = community_id
          and cm.user_id = auth.uid()
          and cm.role in ('admin', 'moderator')
          and cm.status = 'approved'
      )
    )
  );
