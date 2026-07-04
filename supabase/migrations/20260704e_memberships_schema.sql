-- ── Creator / Community Memberships ─────────────────────────────
-- Communities (churches/ministries) offer paid subscriber tiers.
-- v1 note: this purchases ONE billing period (current_period_end =
-- purchase time + tier.interval_days) via the existing one-off
-- payment_transactions flow. True auto-renewal (Stripe Subscriptions /
-- Paystack Plans / a scheduled M-Pesa re-auth push) is a follow-up —
-- for now the subscriber re-purchases when their period lapses.

CREATE TABLE IF NOT EXISTS public.membership_tiers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id  UUID NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  description   TEXT,
  price         NUMERIC(12, 2) NOT NULL CHECK (price > 0),
  currency      TEXT NOT NULL DEFAULT 'KES',
  interval_days INTEGER NOT NULL DEFAULT 30,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_membership_tiers_community
  ON public.membership_tiers(community_id, is_active);

ALTER TABLE public.membership_tiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active tiers"
  ON public.membership_tiers FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "Community creator can manage their tiers"
  ON public.membership_tiers FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.communities c
      WHERE c.id = community_id AND c.created_by = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.communities c
      WHERE c.id = community_id AND c.created_by = auth.uid()
    )
  );

-- ── Subscriptions ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.membership_subscriptions (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  tier_id               UUID NOT NULL REFERENCES public.membership_tiers(id) ON DELETE CASCADE,
  community_id          UUID NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'active', 'expired', 'cancelled')),
  current_period_end    TIMESTAMPTZ,
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_membership_subs_subscriber
  ON public.membership_subscriptions(subscriber_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_membership_subs_community
  ON public.membership_subscriptions(community_id, status);

ALTER TABLE public.membership_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Subscribers can view their own subscriptions"
  ON public.membership_subscriptions FOR SELECT
  USING (subscriber_id = auth.uid());

CREATE POLICY "Community creator can view subscriptions to their tiers"
  ON public.membership_subscriptions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.communities c
      WHERE c.id = community_id AND c.created_by = auth.uid()
    )
  );

CREATE POLICY "Subscribers can create their own subscriptions"
  ON public.membership_subscriptions FOR INSERT
  WITH CHECK (subscriber_id = auth.uid());

CREATE POLICY "Subscribers can update their own subscriptions"
  ON public.membership_subscriptions FOR UPDATE
  USING (subscriber_id = auth.uid())
  WITH CHECK (subscriber_id = auth.uid());

-- ── Gated announcements (subscriber-only content) ────────────────
-- Additive column only. NOTE: the `announcements` table's RLS policies
-- are not defined in this repo's tracked migrations (created directly
-- in the live project) — enforcing this gate at the database level
-- requires auditing those existing policies first. Until that audit
-- happens, treat this column as a client-side-only gate (the Flutter
-- app hides gated content from non-subscribers), NOT a security
-- boundary — a determined client could still read the row via the API.

ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS required_tier_id UUID REFERENCES public.membership_tiers(id) ON DELETE SET NULL;
