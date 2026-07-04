-- ── 1. Add religion column to users table ────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS religion TEXT DEFAULT '' CHECK (religion IN ('christian', 'muslim', ''));

-- ── 2. Add members_count to communities if missing ───────────────
ALTER TABLE public.communities
  ADD COLUMN IF NOT EXISTS members_count INTEGER NOT NULL DEFAULT 0;

-- ── 3. The Holy Bible — default system community ──────────────────
INSERT INTO public.communities (
  id, name, description, hub_type, is_private, members_count,
  cover_url, created_by, created_at
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'The Holy Bible',
  'The complete Bible scripture from Genesis to Revelation — 66 books, 1,189 chapters, Old and New Testament. Open to all believers and seekers.',
  'christianity',
  false,
  0,
  null,
  null,
  now()
) ON CONFLICT (id) DO NOTHING;

-- ── 4. The Holy Quran — default system community ──────────────────
INSERT INTO public.communities (
  id, name, description, hub_type, is_private, members_count,
  cover_url, created_by, created_at
) VALUES (
  '00000000-0000-0000-0000-000000000002',
  'The Holy Quran',
  'The complete Quran from Al-Fatiha to An-Nas — 114 Surahs, 6,236 verses, Meccan and Medinan revelations. Open to all Muslims and those seeking knowledge.',
  'islam',
  false,
  0,
  null,
  null,
  now()
) ON CONFLICT (id) DO NOTHING;
