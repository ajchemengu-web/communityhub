-- ── Account Privacy (private accounts) ───────────────────────────
-- Additive only. NOTE: the `users` table's own migration isn't tracked
-- in this repo (created directly in Supabase Studio, like
-- `announcements`) — this column addition is safe regardless, but any
-- RLS tightening on `users`/`posts` to match would need to be done
-- against whatever policies already exist there, which this repo can't
-- see. Enforcement for now is app-level query filtering — see
-- profile_detail_repository.dart / feed_repository.dart etc.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE;

-- `status` defaults to 'accepted' so every existing follow row (and
-- every future follow of a public account) keeps today's behavior —
-- only following a *private* account inserts a 'pending' row instead.
ALTER TABLE public.follows
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'accepted'
    CHECK (status IN ('pending', 'accepted'));

CREATE INDEX IF NOT EXISTS idx_follows_pending
  ON public.follows(following_id, status) WHERE status = 'pending';
