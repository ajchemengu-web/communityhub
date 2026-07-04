-- ── Payment Transactions Ledger ─────────────────────────────────
-- Single source of truth for every payment-driven feature (giving,
-- marketplace orders, memberships, boosts). All rows are written by
-- Supabase Edge Functions using the service role key — the client
-- app only ever reads its own rows.

CREATE TABLE IF NOT EXISTS public.payment_transactions (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  purpose               TEXT NOT NULL
                          CHECK (purpose IN ('donation', 'order', 'membership', 'boost')),
  reference_id          UUID, -- points at donations/orders/membership_subscriptions/boosts row (no FK — polymorphic)

  provider              TEXT NOT NULL
                          CHECK (provider IN ('stripe', 'paystack', 'mpesa')),
  provider_ref          TEXT, -- Stripe PaymentIntent id / Paystack reference / Daraja CheckoutRequestID

  amount                NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  currency              TEXT NOT NULL DEFAULT 'KES',

  status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'processing', 'succeeded', 'failed', 'cancelled')),

  recipient_type        TEXT NOT NULL DEFAULT 'platform'
                          CHECK (recipient_type IN ('platform', 'community')),
  recipient_id          UUID, -- community_id when recipient_type = 'community'

  platform_fee_amount   NUMERIC(12, 2),
  raw_provider_payload  JSONB,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_user
  ON public.payment_transactions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_provider_ref
  ON public.payment_transactions(provider, provider_ref);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_reference
  ON public.payment_transactions(purpose, reference_id);

-- ── Row Level Security ──────────────────────────────────────────
-- No client-side INSERT/UPDATE policy: all writes go through Edge
-- Functions using the service role key, which bypasses RLS entirely.

ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own transactions"
  ON public.payment_transactions FOR SELECT
  USING (user_id = auth.uid());

-- ── Realtime ─────────────────────────────────────────────────────
-- Lets the Flutter app watch a transaction row resolve — critical
-- for M-Pesa STK push, which has no client SDK to poll against.

ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_transactions;

-- ── updated_at trigger ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_payment_transaction_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_transactions_updated_at ON public.payment_transactions;
CREATE TRIGGER trg_payment_transactions_updated_at
  BEFORE UPDATE ON public.payment_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_payment_transaction_updated_at();
