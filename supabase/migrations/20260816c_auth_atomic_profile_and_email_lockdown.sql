-- ── Auth hardening: atomic profile creation + email/phone lockdown ──
--
-- Two independent fixes bundled together because they're both about
-- the same root problem: `public.users` rows have only ever been
-- created client-side, after the fact, from whatever screen happened
-- to run first. That's both fragile (a dropped connection between
-- auth.signUp() and the client's upsert leaves an orphaned auth user
-- with no profile row) and, combined with the "open by default" SELECT
-- policy installed in 20260706b_posts_users_rls_privacy_blocking.sql,
-- a real PII leak: that policy gates ROWS, not COLUMNS, so any
-- unauthenticated caller holding only the public anon key can already
-- read every user's `email` and `phone` straight off
-- `GET .../rest/v1/users?select=email,phone` — nothing in this repo's
-- tracked migrations restricts those two columns specifically. The
-- app's own login-by-username/phone flow (`_lookupEmail` in
-- auth_provider.dart) depends on being able to do exactly that lookup,
-- which is what made it easy to miss: it looks like a feature, not a
-- hole, until you realize it works for every row, not just your own.
--
-- Like the other untracked-base-table migrations in this repo, this
-- can't know for certain what's live today — it's written to be safe
-- to run regardless (idempotent, additive, no data changes).

-- ═══════════════════════════════════════════════════════════════════
-- PART 1 — atomic profile creation on signup
-- ═══════════════════════════════════════════════════════════════════
--
-- Fires inside the same transaction Supabase Auth uses to create the
-- auth.users row, so there's no window where an account exists in
-- auth.users but not public.users. Username comes from the signup
-- metadata the app already sends (register_screen.dart /
-- otp_screen.dart both pass `data: {'username': ..., 'full_name': ...}`
-- into signUp()/signInWithOtp()) — OAuth signups (Google) don't have a
-- username in their metadata, so those fall back to an id-derived
-- placeholder; the app's setup-profile screen (currently orphaned —
-- see the auth audit) is the intended place for that user to pick a
-- real one afterward.
--
-- SECURITY DEFINER is required (the function must run with the
-- privileges to insert into public.users regardless of who's calling
-- it — a brand-new, not-yet-authenticated signup has no session yet
-- to satisfy a normal RLS check). `SET search_path = ''` + fully
-- qualified names is the standard mitigation for the
-- search-path-hijack risk that comes with SECURITY DEFINER.
--
-- `id` and `username` are assumed to exist and to have a unique
-- constraint on `id` — safe assumptions, since every other tracked
-- migration's `REFERENCES public.users(id)` requires that to already
-- be true. Every OTHER column here (full_name, email, phone,
-- is_verified) is checked against information_schema first and only
-- included in the INSERT if it's actually there, rather than assumed
-- from what the Dart app happens to write — that assumption is what
-- broke PART 2 below on the first attempt at this migration
-- (`updated_at` doesn't exist on the live table despite
-- profile_repository.dart writing it — from the setup-profile screen,
-- which per the auth audit is orphaned and has apparently never
-- actually run against production). A broken INSERT here is much
-- worse than a broken GRANT: it would fail on the AFTER INSERT trigger
-- and take the whole signup down with it, so this is worth being
-- extra careful about.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  base_username TEXT;
  final_username TEXT;
  full_name_value TEXT;
  attempt INT := 0;
  cols TEXT[] := ARRAY['id', 'username'];
  vals TEXT[];
  i INT;
BEGIN
  base_username := NULLIF(TRIM(NEW.raw_user_meta_data->>'username'), '');

  IF base_username IS NULL AND NEW.email IS NOT NULL THEN
    base_username := split_part(NEW.email, '@', 1);
  END IF;

  IF base_username IS NULL THEN
    base_username := 'user_' || substr(NEW.id::text, 1, 8);
  END IF;

  final_username := base_username;
  full_name_value := COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''), final_username);

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'full_name') THEN
    cols := cols || 'full_name';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'email') THEN
    cols := cols || 'email';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'phone') THEN
    cols := cols || 'phone';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'is_verified') THEN
    cols := cols || 'is_verified';
  END IF;

  -- Username has a UNIQUE constraint (see isUsernameAvailable() in
  -- profile_repository.dart) but nothing upstream of this trigger
  -- guarantees uniqueness for the OAuth/fallback paths above — retry
  -- with a numbered suffix instead of failing the entire signup.
  -- Bounded at 50 attempts; if it's still colliding after that,
  -- something else is wrong and it's better to surface that error
  -- than mask it behind an ever-growing suffix.
  LOOP
    attempt := attempt + 1;
    IF attempt > 1 THEN
      final_username := base_username || '_' || (attempt - 1)::text;
    END IF;

    BEGIN
      vals := ARRAY[]::TEXT[];
      FOR i IN 1..array_length(cols, 1) LOOP
        vals := vals || (CASE cols[i]
          WHEN 'id' THEN format('%L::uuid', NEW.id)
          WHEN 'username' THEN format('%L', final_username)
          WHEN 'full_name' THEN format('%L', full_name_value)
          WHEN 'email' THEN format('%L', NEW.email)
          WHEN 'phone' THEN format('%L', NEW.phone)
          WHEN 'is_verified' THEN 'FALSE'
        END);
      END LOOP;

      EXECUTE format(
        'INSERT INTO public.users (%s) VALUES (%s) ON CONFLICT (id) DO NOTHING',
        array_to_string(cols, ', '),
        array_to_string(vals, ', ')
      );
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF attempt > 50 THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- The Dart-side upsert in auth_provider.dart's signUpWithEmail() stays
-- in place as a defensive backstop (e.g. against this migration not
-- having been applied to some environment yet) — by the time it runs,
-- this trigger will already have created the row, so it just becomes
-- a harmless no-op UPDATE with identical values.

-- ═══════════════════════════════════════════════════════════════════
-- PART 2 — stop exposing email/phone/fcm_token to the anon/authenticated
-- roles at the column-privilege level (defense in depth under RLS)
-- ═══════════════════════════════════════════════════════════════════
--
-- RLS policies restrict which ROWS a role can see; they say nothing
-- about which COLUMNS. Postgres's ordinary column-privilege system is
-- the layer that's supposed to do that, and nothing in this repo's
-- tracked migrations ever narrowed it — so once the "open by default"
-- SELECT policy from 20260706b applies, every column of every visible
-- row (including email, phone, and the fcm_token push-notification
-- token) is readable by anyone with the public anon key.
--
-- Nothing in the app's own code needs to read another user's email,
-- phone, or fcm_token (confirmed by grepping lib/ for `.select(...)`
-- on this table) — the one place that used to (the username/phone
-- login lookup) is being moved to the SECURITY DEFINER function below
-- instead, which only ever returns a single email for an exact
-- username/phone match, not the column in bulk.
--
-- `users` is one of the tables created directly in Supabase Studio
-- (not through a tracked migration — see the note at the top of this
-- file and 20260706b), so this repo can't be fully sure of its exact
-- column list. A first version of this migration hardcoded the
-- expected "safe" columns from what the Dart app writes/reads, and
-- that guess was wrong (it included `updated_at`, which the setup-
-- profile screen's code writes but which — like that whole screen —
-- has apparently never actually run against production, since the
-- column doesn't exist there). Rather than guess again, this grants
-- SELECT on every column of `users` EXCEPT the three sensitive ones,
-- discovered dynamically against whatever the table actually has.

REVOKE SELECT ON public.users FROM anon, authenticated;

DO $$
DECLARE
  safe_columns TEXT;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
  INTO safe_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'users'
    AND column_name NOT IN ('email', 'phone', 'fcm_token');

  IF safe_columns IS NULL THEN
    RAISE EXCEPTION 'public.users has no columns outside the excluded set — check the table exists and its column names';
  END IF;

  EXECUTE format(
    'GRANT SELECT (%s) ON public.users TO anon, authenticated',
    safe_columns
  );
END $$;

-- Login-by-username-or-phone: a narrow, purpose-built replacement for
-- the two direct `.select('email')` queries this used to run against
-- the table (see auth_provider.dart's _lookupEmail). Still ultimately
-- an "does this identifier exist" oracle — that's inherent to any
-- login-by-username feature, not something this function introduces —
-- but it can no longer be used to bulk-dump every user's email/phone
-- in one request, only to probe one identifier at a time.
CREATE OR REPLACE FUNCTION public.lookup_email_for_identifier(identifier TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  found_email TEXT;
  normalized_phone TEXT;
BEGIN
  SELECT u.email INTO found_email
  FROM public.users u
  WHERE u.username = identifier
  LIMIT 1;

  IF found_email IS NOT NULL THEN
    RETURN found_email;
  END IF;

  normalized_phone := CASE
    WHEN identifier LIKE '+%' THEN identifier
    ELSE '+' || identifier
  END;

  SELECT u.email INTO found_email
  FROM public.users u
  WHERE u.phone = normalized_phone
  LIMIT 1;

  RETURN found_email; -- NULL when nothing matched; caller handles that
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_email_for_identifier(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_email_for_identifier(TEXT) TO anon, authenticated;
