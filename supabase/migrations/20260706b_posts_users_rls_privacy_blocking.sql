-- ── DB-level RLS for blocking + private accounts ─────────────────
--
-- Read this before applying. The `posts` and `users` tables' own
-- migrations aren't tracked in this repo (they were created directly
-- in Supabase Studio), so this migration can't know exactly what SELECT
-- policies already exist on them. Rather than guess policy names to
-- drop, it dynamically discovers and drops *every* existing SELECT
-- policy on these two tables, then installs one consolidated policy
-- each that reproduces "open by default" while adding the block/privacy
-- carve-outs.
--
-- Only SELECT policies are touched — INSERT/UPDATE/DELETE policies on
-- both tables are left completely alone.
--
-- >>> If either table currently has a SELECT policy serving some other
-- >>> purpose you know about and I don't (e.g. an admin/moderator
-- >>> bypass, a moderation_status gate, a paid-content gate), review
-- >>> this file and fold that condition into the new policy below
-- >>> before running it — this migration has no way to discover intent,
-- >>> only the mechanical shape of what's there.
--
-- What's enforced after this runs:
-- • posts: hidden from a viewer if either party has blocked the other,
--   or if the author is a private account and the viewer isn't an
--   accepted follower (and isn't the author). Anonymous/unauthenticated
--   reads count as "not a follower", so private posts are hidden from
--   them too.
-- • users: hidden from a viewer if either party has blocked the other.
--   Privacy does NOT hide the profile row itself (name/avatar/bio stay
--   visible for private accounts, matching how the app already renders
--   a profile header before gating the posts grid) — only `posts` gates
--   content.

DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'posts' AND cmd = 'SELECT'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.posts', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "Posts hidden from blockers and from private non-followers"
  ON public.posts FOR SELECT
  USING (
    author_id = auth.uid()
    OR (
      NOT EXISTS (
        SELECT 1 FROM public.user_blocks b
        WHERE (b.blocker_id = auth.uid() AND b.blocked_id = posts.author_id)
           OR (b.blocker_id = posts.author_id AND b.blocked_id = auth.uid())
      )
      AND (
        NOT EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = posts.author_id AND u.is_private = TRUE
        )
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.following_id = posts.author_id
            AND f.status = 'accepted'
        )
      )
    )
  );

DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND cmd = 'SELECT'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.users', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "User profiles hidden between accounts that blocked each other"
  ON public.users FOR SELECT
  USING (
    id = auth.uid()
    OR NOT EXISTS (
      SELECT 1 FROM public.user_blocks b
      WHERE (b.blocker_id = auth.uid() AND b.blocked_id = users.id)
         OR (b.blocker_id = users.id AND b.blocked_id = auth.uid())
    )
  );
