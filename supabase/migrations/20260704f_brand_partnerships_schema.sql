-- ── Branded Content (disclosed brand/community partnerships) ─────
-- v1 is intentionally manual: partnerships are created and approved
-- directly in Supabase Studio (or a future admin tool), not self-serve
-- in the app. The app only ever reads approved rows to render a
-- disclosure badge — no payment integration yet.

CREATE TABLE IF NOT EXISTS public.brand_partnerships (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id      UUID NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  brand_name        TEXT NOT NULL,
  description       TEXT,
  disclosure_label  TEXT NOT NULL DEFAULT 'Paid Partnership',
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes       TEXT,
  starts_at         TIMESTAMPTZ,
  ends_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_brand_partnerships_community
  ON public.brand_partnerships(community_id, status);

ALTER TABLE public.brand_partnerships ENABLE ROW LEVEL SECURITY;

-- Anyone can see an *approved* (and currently active, if dated) partnership
-- so the disclosure badge can render — this is a disclosure, not a secret.
CREATE POLICY "Anyone can view approved partnerships"
  ON public.brand_partnerships FOR SELECT
  USING (
    status = 'approved'
    AND (starts_at IS NULL OR starts_at <= NOW())
    AND (ends_at IS NULL OR ends_at >= NOW())
  );

CREATE POLICY "Community creator can view their own partnerships"
  ON public.brand_partnerships FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.communities c
      WHERE c.id = community_id AND c.created_by = auth.uid()
    )
  );

-- No client INSERT/UPDATE policy — v1 partnerships are created and
-- approved directly in Supabase Studio by CommunityHub staff.
