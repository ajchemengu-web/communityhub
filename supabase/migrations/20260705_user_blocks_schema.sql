-- ── User Blocks ──────────────────────────────────────────────────
-- A row is visible to either party involved — the blocker needs to see
-- their own block list to manage it, and the blocked party needs to see
-- it too so their own client can filter out the blocker's content
-- without needing to expose the block list to anyone else.

CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked
  ON public.user_blocks(blocked_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Either party can view a block involving them"
  ON public.user_blocks FOR SELECT
  USING (blocker_id = auth.uid() OR blocked_id = auth.uid());

CREATE POLICY "Users can block on their own behalf"
  ON public.user_blocks FOR INSERT
  WITH CHECK (blocker_id = auth.uid());

CREATE POLICY "Users can unblock on their own behalf"
  ON public.user_blocks FOR DELETE
  USING (blocker_id = auth.uid());
