-- ── Boosted Posts / Events ───────────────────────────────────────
-- Self-serve "promote this" — a one-off payment ranks a post or event
-- higher for a time window. Visible to everyone (not just the buyer),
-- since the whole point is wider reach.

CREATE TABLE IF NOT EXISTS public.boosts (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type           TEXT NOT NULL CHECK (target_type IN ('post', 'event')),
  target_id             UUID NOT NULL,
  buyer_id              UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  starts_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at               TIMESTAMPTZ NOT NULL,
  rank_weight           NUMERIC NOT NULL DEFAULT 1,
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_boosts_active
  ON public.boosts(target_type, ends_at DESC) WHERE ends_at > NOW();

CREATE INDEX IF NOT EXISTS idx_boosts_target
  ON public.boosts(target_type, target_id);

CREATE INDEX IF NOT EXISTS idx_boosts_buyer
  ON public.boosts(buyer_id, created_at DESC);

ALTER TABLE public.boosts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active boosts"
  ON public.boosts FOR SELECT
  USING (ends_at > NOW());

CREATE POLICY "Buyers can view their own boosts regardless of status"
  ON public.boosts FOR SELECT
  USING (buyer_id = auth.uid());

CREATE POLICY "Buyers can create their own boosts"
  ON public.boosts FOR INSERT
  WITH CHECK (buyer_id = auth.uid());

CREATE POLICY "Buyers can attach a payment transaction to their boost"
  ON public.boosts FOR UPDATE
  USING (buyer_id = auth.uid())
  WITH CHECK (buyer_id = auth.uid());
