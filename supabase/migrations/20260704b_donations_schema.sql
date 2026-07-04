-- ── Donations (tithing / giving) ────────────────────────────────
-- A donation row is created client-side the moment the giver picks an
-- amount, before any money moves. `payment_transaction_id` is attached
-- right after a charge is initiated; the donation is only considered
-- "given" once the linked payment_transactions row reaches 'succeeded'.

CREATE TABLE IF NOT EXISTS public.donations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  giver_id              UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  community_id          UUID REFERENCES public.communities(id) ON DELETE SET NULL, -- null = general platform give
  amount                NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  currency              TEXT NOT NULL DEFAULT 'KES',
  message               TEXT,
  is_anonymous          BOOLEAN NOT NULL DEFAULT FALSE,
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_donations_giver
  ON public.donations(giver_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_donations_community
  ON public.donations(community_id, created_at DESC);

ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Givers can view their own donations"
  ON public.donations FOR SELECT
  USING (giver_id = auth.uid());

CREATE POLICY "Givers can create their own donations"
  ON public.donations FOR INSERT
  WITH CHECK (giver_id = auth.uid());

CREATE POLICY "Givers can attach a payment transaction to their donation"
  ON public.donations FOR UPDATE
  USING (giver_id = auth.uid())
  WITH CHECK (giver_id = auth.uid());
