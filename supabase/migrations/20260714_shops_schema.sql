-- ── Shops (marketplace storefronts) ──────────────────────────────
-- Revives the "shop" concept on top of the existing products/orders
-- tables from 20260704d_marketplace_schema.sql: one shop per seller,
-- managed from the profile section, whose inventory (their `products`
-- rows) surfaces in the marketplace. Design follows the standard
-- storefront pattern (Etsy/Instagram Shop/Amazon seller pages): browse
-- in the marketplace -> tap a product -> product detail page -> tap the
-- seller header to visit their full storefront. See product_detail
-- and marketplace redesign for the client side of that flow.
--
-- shops.id doubles as the FK to users(id) rather than a separate
-- generated UUID -- a shop is a 1:1 extension of a seller's account, so
-- "does this user have a shop" and "look up their shop" are both a
-- direct primary-key lookup, and the storefront route can be
-- /shop/<user_id> with no extra join needed.

CREATE TABLE IF NOT EXISTS public.shops (
  id            UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  bio           TEXT,
  banner_url    TEXT,
  logo_url      TEXT,
  category      TEXT, -- freeform "what this shop mostly sells" label shown on the storefront; independent of individual products' `type`
  is_published  BOOLEAN NOT NULL DEFAULT FALSE, -- draft until the owner explicitly publishes, same pattern as products.is_active and Profolio's portfolios.is_published
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shops_published
  ON public.shops(is_published, created_at DESC);

CREATE OR REPLACE FUNCTION public.set_shops_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_shops_updated_at ON public.shops;
CREATE TRIGGER trg_shops_updated_at
  BEFORE UPDATE ON public.shops
  FOR EACH ROW EXECUTE FUNCTION public.set_shops_updated_at();

ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;

-- Anyone can view a published shop (the public storefront page).
CREATE POLICY "Anyone can view published shops"
  ON public.shops FOR SELECT
  USING (is_published = TRUE);

-- Owners can always see their own shop, published or still a draft.
CREATE POLICY "Owners can view their own shop regardless of status"
  ON public.shops FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "Owners can create their own shop"
  ON public.shops FOR INSERT
  WITH CHECK (id = auth.uid());

CREATE POLICY "Owners can update their own shop"
  ON public.shops FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "Owners can delete their own shop"
  ON public.shops FOR DELETE
  USING (id = auth.uid());

-- ── Marketplace search ───────────────────────────────────────────
-- Backs the new marketplace search bar (ILIKE on title/description).
-- pg_trgm gives ILIKE a usable index instead of a full table scan once
-- the listings table grows past a trivial size.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_products_title_trgm
  ON public.products USING GIN (title gin_trgm_ops);
