-- ── Post Audio Track ─────────────────────────────────────────────
-- `posts` isn't tracked in this repo (created directly in Studio), so
-- these are additive-only columns — safe on an existing live table.
-- Stores the iTunes-sourced track a user attaches to a post (image
-- posts get real preview playback; video posts just show attribution
-- since mixing audio into the video file needs real video re-encoding,
-- out of scope for now).

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS audio_title TEXT,
  ADD COLUMN IF NOT EXISTS audio_artist TEXT,
  ADD COLUMN IF NOT EXISTS audio_preview_url TEXT;
