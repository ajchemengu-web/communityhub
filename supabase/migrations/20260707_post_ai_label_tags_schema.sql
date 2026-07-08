-- ── AI-generated label + Tag People ──────────────────────────────
-- `posts` isn't tracked in this repo (created directly in Studio), so
-- `is_ai_generated` is an additive-only column — safe on an existing
-- live table since it doesn't touch any existing policy or data.
--
-- `post_tags` is new and fully tracked here. A tag is visible to
-- anyone who can already see the post (tags aren't sensitive on their
-- own), but only the post's author can create tags on their post, and
-- either the author or the tagged person can remove one — mirrors
-- Instagram's "remove yourself from a photo" behavior.

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS is_ai_generated BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS public.post_tags (
  id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tagged_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, tagged_user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_tags_post ON public.post_tags(post_id);
CREATE INDEX IF NOT EXISTS idx_post_tags_user ON public.post_tags(tagged_user_id);

ALTER TABLE public.post_tags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tags are visible to anyone"
  ON public.post_tags FOR SELECT
  USING (true);

CREATE POLICY "Only the post author can tag people on their post"
  ON public.post_tags FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id AND p.author_id = auth.uid()
    )
  );

CREATE POLICY "Author or the tagged person can remove a tag"
  ON public.post_tags FOR DELETE
  USING (
    tagged_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id AND p.author_id = auth.uid()
    )
  );
