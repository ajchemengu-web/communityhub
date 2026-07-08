-- ── Story Audience Restriction, Muting, and Real Privacy ─────────
-- Stories previously had a fully permissive "viewable by all" SELECT
-- policy — no private-account check, no per-story audience control.
-- This replaces it with WhatsApp-style behavior: a private account's
-- base audience is its accepted followers (same rule already enforced
-- for posts), and the story owner can further narrow any single story
-- to "All Followers" (default), "All Followers Except [list]", or
-- "Only Share With [list]".

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS audience_mode TEXT NOT NULL DEFAULT 'all_followers'
    CHECK (audience_mode IN ('all_followers', 'all_except', 'only_these'));

-- Holds the exception list for 'all_except' (excluded viewers) and the
-- inclusion list for 'only_these' (the only allowed viewers) — which
-- one it means depends on stories.audience_mode for that row.
CREATE TABLE IF NOT EXISTS public.story_audience_exceptions (
  story_id  UUID NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  PRIMARY KEY (story_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_story_audience_exceptions_story
  ON public.story_audience_exceptions(story_id);

ALTER TABLE public.story_audience_exceptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Exceptions visible to the story owner and the listed user"
  ON public.story_audience_exceptions FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.stories s
      WHERE s.id = story_id AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "Only the story owner can set audience exceptions"
  ON public.story_audience_exceptions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.stories s
      WHERE s.id = story_id AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "Only the story owner can remove audience exceptions"
  ON public.story_audience_exceptions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.stories s
      WHERE s.id = story_id AND s.user_id = auth.uid()
    )
  );

-- ── Muting someone's status updates ───────────────────────────────
-- Muting only affects where their updates show up in your own Updates
-- list (moved out of "Recent") — it never affects what they can see of
-- yours, so this has no bearing on the stories SELECT policy below.
CREATE TABLE IF NOT EXISTS public.story_mutes (
  muter_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  muted_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (muter_id, muted_id),
  CHECK (muter_id <> muted_id)
);

ALTER TABLE public.story_mutes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own mute list"
  ON public.story_mutes FOR SELECT
  USING (muter_id = auth.uid());

CREATE POLICY "Users can mute on their own behalf"
  ON public.story_mutes FOR INSERT
  WITH CHECK (muter_id = auth.uid());

CREATE POLICY "Users can unmute on their own behalf"
  ON public.story_mutes FOR DELETE
  USING (muter_id = auth.uid());

-- ── Replace the permissive stories SELECT policy ──────────────────
DROP POLICY IF EXISTS "Stories viewable by all" ON public.stories;

CREATE POLICY "Stories respect privacy, blocking, and per-story audience"
  ON public.stories FOR SELECT
  USING (
    user_id = auth.uid()
    OR (
      -- Blocking (either direction)
      NOT EXISTS (
        SELECT 1 FROM public.user_blocks b
        WHERE (b.blocker_id = auth.uid() AND b.blocked_id = stories.user_id)
           OR (b.blocker_id = stories.user_id AND b.blocked_id = auth.uid())
      )
      -- Private-account base visibility — same rule already enforced
      -- for posts: public accounts are open, private accounts require
      -- an accepted follow.
      AND (
        NOT EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = stories.user_id AND u.is_private = TRUE
        )
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.following_id = stories.user_id
            AND f.status = 'accepted'
        )
      )
      -- Per-story audience narrowing on top of the base visibility above.
      AND (
        stories.audience_mode = 'all_followers'
        OR (
          stories.audience_mode = 'all_except'
          AND NOT EXISTS (
            SELECT 1 FROM public.story_audience_exceptions e
            WHERE e.story_id = stories.id AND e.user_id = auth.uid()
          )
        )
        OR (
          stories.audience_mode = 'only_these'
          AND EXISTS (
            SELECT 1 FROM public.story_audience_exceptions e
            WHERE e.story_id = stories.id AND e.user_id = auth.uid()
          )
        )
      )
    )
  );
