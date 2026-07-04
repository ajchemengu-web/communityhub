-- ── Marketplace (social commerce) ────────────────────────────────
-- Communities/ministries sell merch, books, courses and event tickets.
-- CommunityHub takes a platform cut, recorded on the order row.

CREATE TABLE IF NOT EXISTS public.products (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  community_id  UUID REFERENCES public.communities(id) ON DELETE SET NULL,
  type          TEXT NOT NULL DEFAULT 'merch'
                  CHECK (type IN ('merch', 'book', 'course', 'ticket')),
  title         TEXT NOT NULL,
  description   TEXT,
  price         NUMERIC(12, 2) NOT NULL CHECK (price > 0),
  currency      TEXT NOT NULL DEFAULT 'KES',
  images        TEXT[] NOT NULL DEFAULT '{}',
  stock         INTEGER, -- null = unlimited (digital/course/ticket with no cap)
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_active
  ON public.products(is_active, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_products_seller
  ON public.products(seller_id, created_at DESC);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active products"
  ON public.products FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "Sellers can view their own products regardless of status"
  ON public.products FOR SELECT
  USING (seller_id = auth.uid());

CREATE POLICY "Sellers can create their own products"
  ON public.products FOR INSERT
  WITH CHECK (seller_id = auth.uid());

CREATE POLICY "Sellers can update their own products"
  ON public.products FOR UPDATE
  USING (seller_id = auth.uid())
  WITH CHECK (seller_id = auth.uid());

-- ── Orders ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id              UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  product_id            UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  seller_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  quantity              INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  amount                NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  currency              TEXT NOT NULL DEFAULT 'KES',
  platform_fee_amount   NUMERIC(12, 2),
  fulfillment_status    TEXT NOT NULL DEFAULT 'pending'
                          CHECK (fulfillment_status IN ('pending', 'paid', 'shipped', 'completed', 'cancelled')),
  shipping_info         JSONB,
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_buyer
  ON public.orders(buyer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_seller
  ON public.orders(seller_id, created_at DESC);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Buyers can view their own orders"
  ON public.orders FOR SELECT
  USING (buyer_id = auth.uid());

CREATE POLICY "Sellers can view orders for their products"
  ON public.orders FOR SELECT
  USING (seller_id = auth.uid());

CREATE POLICY "Buyers can create their own orders"
  ON public.orders FOR INSERT
  WITH CHECK (buyer_id = auth.uid());

CREATE POLICY "Buyers can attach a payment transaction to their order"
  ON public.orders FOR UPDATE
  USING (buyer_id = auth.uid())
  WITH CHECK (buyer_id = auth.uid());

CREATE POLICY "Sellers can update fulfillment status on their orders"
  ON public.orders FOR UPDATE
  USING (seller_id = auth.uid())
  WITH CHECK (seller_id = auth.uid());

-- ── Ticketed events link ──────────────────────────────────────────
-- Lets an event reuse the marketplace/orders flow for paid tickets
-- instead of forking a separate payment path.

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_paid BOOLEAN NOT NULL DEFAULT FALSE;
