-- ============================================================
-- Communities Phase 1: RLS hardening + announcements table fix
-- ============================================================
-- Written against a live-schema audit performed via Supabase Studio's
-- SQL editor (core communities tables were created directly in the
-- live project and were never in a tracked migration -- see the note
-- in 20260704e_memberships_schema.sql). Two independent problems were
-- found:
--
--   1. SECURITY: community_members had an INSERT policy with
--      `with_check: true` -- no restriction at all. Any authenticated
--      user could insert a row granting themselves role='admin' in
--      ANY community, completely bypassing the join/approval flow.
--   2. The `announcements` feature has been broken in production:
--      communities_repository.dart queries `.from('announcements')`
--      (see fetchAnnouncements/postAnnouncement), and migration
--      20260704e tried to ALTER TABLE public.announcements -- but the
--      table that actually exists live is named
--      `community_announcements`. Every announcement fetch/post has
--      been failing silently against a table that doesn't exist under
--      the name the app queries.
--
-- Also folded in here: the `communities` table had duplicate,
-- overlapping RLS policies (one set keyed on `created_by`, which the
-- app never writes to -- only `creator_id` is ever set by
-- createCommunity() -- the other keyed on `creator_id`). Because
-- Postgres RLS policies for the same command are OR'd together, the
-- redundant pair on INSERT silently made the restrictive policy
-- meaningless (one of the two had `with_check: true`). Consolidated
-- into one policy per command, all keyed on `creator_id` +
-- community_members.role = 'admin' (status = 'approved'), matching
-- the role-based model the app's Dart code already uses everywhere
-- else (CommunityModel.userRole, not a `created_by` column).
--
-- Safe to run multiple times (idempotent where practical).
-- ============================================================

begin;

-- ── 1. communities: drop redundant/open policies, keep one
--    consistent, role-aware policy per command ─────────────────────

-- INSERT: "authenticated users can create communities" had no
-- restriction (with_check: true), which -- because permissive
-- policies for the same command are OR'd -- made the properly
-- restrictive "communities_insert" (creator_id = auth.uid()) policy
-- meaningless. Drop the open one; the restrictive one already matches
-- what createCommunity() sends and needs no change.
drop policy if exists "authenticated users can create communities" on public.communities;

-- DELETE: replace the two overlapping policies (one on the unused
-- `created_by` column, one on `creator_id` with no admin-role
-- allowance) with a single policy: the creator, OR an approved
-- community_members admin, may delete.
drop policy if exists "admins can delete community" on public.communities;
drop policy if exists "communities_delete" on public.communities;
create policy "communities_delete" on public.communities
  for delete
  to authenticated
  using (
    creator_id = auth.uid()
    or exists (
      select 1 from public.community_members cm
      where cm.community_id = communities.id
        and cm.user_id = auth.uid()
        and cm.role = 'admin'
        and cm.status = 'approved'
    )
  );

-- UPDATE: same consolidation, and add the approved-status requirement
-- to the admin branch (the old communities_update allowed any
-- community_members row with role='admin' regardless of status).
drop policy if exists "admins can update community" on public.communities;
drop policy if exists "communities_update" on public.communities;
create policy "communities_update" on public.communities
  for update
  to authenticated
  using (
    creator_id = auth.uid()
    or exists (
      select 1 from public.community_members cm
      where cm.community_id = communities.id
        and cm.user_id = auth.uid()
        and cm.role = 'admin'
        and cm.status = 'approved'
    )
  );

-- ── 2. community_members: close the privilege-escalation hole ──────
-- The app only ever inserts role='admin' once -- immediately after
-- creating a community, for the creator themselves
-- (createCommunity()). Every other insert path (joinCommunity(), bulk
-- add-members) uses role='member'. This policy now enforces exactly
-- that: you may only ever insert a row for yourself, and you may only
-- claim 'admin' if you are the creator of that community.
drop policy if exists "members_insert" on public.community_members;
create policy "members_insert" on public.community_members
  for insert
  to authenticated
  with check (
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
  );

-- ── 3. is_community_member(): a 'pending' join request currently
--    counts as membership, letting an unapproved requester see
--    private-community content gated by this function (events,
--    announcements, etc). Require status = 'approved', matching how
--    community_channels' own admin-check policy already treats
--    status.
create or replace function public.is_community_member(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from community_members
    where community_id = p_community_id
      and user_id = auth.uid()
      and status = 'approved'
  );
$function$;

-- ── 4. Fix the announcements table name mismatch ────────────────────
-- Renaming preserves all existing data and RLS policies (Postgres
-- policies are attached to the table's OID, not its name), and makes
-- the live schema match what communities_repository.dart and every
-- migration file already assume.
alter table if exists public.community_announcements
  rename to announcements;

-- NOTE: 20260704e_memberships_schema.sql also tries to add a
-- `required_tier_id uuid references public.membership_tiers(id)`
-- column here -- deliberately NOT re-run in this migration. That
-- table doesn't exist live either (confirmed: "relation
-- public.membership_tiers does not exist"), meaning 20260704e was
-- never actually applied to production at all, not just its
-- announcements ALTER. Membership tiers are Phase 3 (monetization)
-- scope, not this Phase 1 pass -- pulling that table into existence
-- here just to satisfy an unrelated column's FK would be scope creep.
-- When Phase 3 is built, run 20260704e's CREATE TABLE statements for
-- membership_tiers/membership_subscriptions first, then this
-- required_tier_id column can be added safely.

commit;
