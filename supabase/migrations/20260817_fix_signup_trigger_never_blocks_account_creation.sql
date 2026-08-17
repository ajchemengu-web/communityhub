-- ── Fix: new signups failing entirely ─────────────────────────────
--
-- Root cause: on_auth_user_created (installed by
-- 20260816c_auth_atomic_profile_and_email_lockdown.sql) runs AFTER
-- INSERT ON auth.users, in the SAME transaction Supabase Auth uses to
-- create the account. If handle_new_user() raises ANY exception it
-- doesn't already know how to handle, Postgres rolls back that whole
-- transaction -- including the auth.users insert -- so the signup
-- fails outright and the person sees a generic "Database error saving
-- new user" from Supabase Auth. The trigger only ever caught
-- unique_violation (an expected case, handled by retrying with a
-- numbered username suffix); anything else -- a NOT NULL or CHECK
-- constraint on a public.users column this migration doesn't already
-- special-case, for instance -- was left to propagate and take the
-- signup down with it.
--
-- This wraps the whole profile-creation attempt in an outer
-- EXCEPTION WHEN OTHERS handler: on any unexpected failure it logs a
-- warning (visible in the Postgres logs, Dashboard → Logs → Postgres
-- Logs, searchable for "handle_new_user") and lets the signup
-- continue rather than blocking it. That trades away this trigger's
-- original atomicity guarantee in the rare unexpected-failure case,
-- but two things already exist specifically to paper over a
-- profile-less auth user afterward: the client-side upsert backstop
-- in signUpWithEmail() (auth_provider.dart), and the stub-row
-- self-heal in ProfileDetailRepository.fetchProfile() for the
-- CURRENT user's own row. A signup that can't be completed at all is
-- a much worse failure mode than an occasional row that needs to
-- self-heal on next load.
--
-- Once this is deployed, check the Postgres logs for any
-- "handle_new_user:" warnings from signups that failed before this
-- fix went out -- that message includes the exact SQLERRM, which
-- will point at whatever public.users constraint the original
-- migration didn't account for, so it can be added to the dynamic
-- column list properly instead of just being swallowed going forward.

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
    -- guarantees uniqueness for the OAuth/fallback paths above --
    -- retry with a numbered suffix instead of failing. Bounded at 50
    -- attempts; if it's still colliding after that, the RAISE below
    -- hands off to the outer handler instead of taking the signup
    -- down with it.
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
  EXCEPTION WHEN OTHERS THEN
    -- Never block the signup itself over a profile-row problem --
    -- see the header comment above for why, and how to find the root
    -- cause afterward via this warning.
    RAISE WARNING 'handle_new_user: could not create public.users row for % (email=%, phone=%): %',
      NEW.id, NEW.email, NEW.phone, SQLERRM;
  END;

  RETURN NEW;
END;
$$;
