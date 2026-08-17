-- Backfills public.users rows for every auth.users account that ended
-- up with no profile row -- confirmed happening in production (Logs →
-- Postgres Logs showed real accounts created 2026-08-17, with
-- completely normal signup metadata, still had no public.users row).
-- This is the same root symptom reported three separate ways: the
-- profile screen falling back to the "Unknown user" stub, community
-- creation failing with `communities_creator_id_fkey ... Key is not
-- present in table "users"`, and Edit Profile silently no-oping (a
-- plain UPDATE against a nonexistent row matches zero rows without
-- erroring at all).
--
-- The exact reason the signup trigger's own INSERT doesn't always
-- leave a row is still not fully pinned down -- it's caught and
-- logged as a WARNING by handle_new_user() (see
-- 20260817_fix_signup_trigger_never_blocks_account_creation.sql) so
-- it never blocks signup, but that also means it never surfaces to
-- the client. This backfill repairs every account affected by it
-- *right now*; profile_detail_repository.dart's updateProfile() was
-- separately changed to upsert instead of update, so editing a
-- profile self-heals this going forward even if the trigger fails
-- again for some future signup.
--
-- Mirrors handle_new_user()'s own username-derivation / retry-on-
-- collision logic so backfilled rows look identical to what the
-- trigger would have created. Idempotent and safe to re-run: only
-- touches auth.users rows with no public.users counterpart yet.
DO $$
DECLARE
  au RECORD;
  base_username TEXT;
  final_username TEXT;
  full_name_value TEXT;
  attempt INT;
BEGIN
  FOR au IN
    SELECT u.id, u.email, u.phone, u.raw_user_meta_data
    FROM auth.users u
    LEFT JOIN public.users pu ON pu.id = u.id
    WHERE pu.id IS NULL
  LOOP
    base_username := NULLIF(TRIM(au.raw_user_meta_data->>'username'), '');
    IF base_username IS NULL AND au.email IS NOT NULL THEN
      base_username := split_part(au.email, '@', 1);
    END IF;
    IF base_username IS NULL THEN
      base_username := 'user_' || substr(au.id::text, 1, 8);
    END IF;

    full_name_value := COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'full_name'), ''), base_username);

    final_username := base_username;
    attempt := 0;
    LOOP
      attempt := attempt + 1;
      IF attempt > 1 THEN
        final_username := base_username || '_' || (attempt - 1)::text;
      END IF;

      BEGIN
        INSERT INTO public.users (id, username, full_name, email, phone, is_verified)
        VALUES (au.id, final_username, full_name_value, au.email, au.phone, FALSE)
        ON CONFLICT (id) DO NOTHING;
        EXIT;
      EXCEPTION
        WHEN unique_violation THEN
          IF attempt > 50 THEN
            RAISE WARNING 'backfill: could not create public.users row for % after 50 username attempts', au.id;
            EXIT;
          END IF;
        WHEN OTHERS THEN
          RAISE WARNING 'backfill: could not create public.users row for % (email=%, phone=%): %', au.id, au.email, au.phone, SQLERRM;
          EXIT;
      END;
    END LOOP;
  END LOOP;
END $$;
