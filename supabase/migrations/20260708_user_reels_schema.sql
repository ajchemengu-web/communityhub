-- ── User-Generated Reels ─────────────────────────────────────────
-- `posts` isn't tracked in this repo (created directly in Studio), so
-- `is_reel` is an additive-only column — safe on an existing live table.
-- Reels are otherwise ordinary posts (same table, same RLS, same
-- likes/comments) — `is_reel` just marks the ones that should also
-- surface in the Reels feed alongside YouTube content.

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS is_reel BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_posts_is_reel
  ON public.posts(is_reel, created_at DESC)
  WHERE is_reel = TRUE;
