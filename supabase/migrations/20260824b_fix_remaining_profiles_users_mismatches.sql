-- ============================================================
-- Fix the remaining functions that read/write the stale `profiles`
-- table instead of `users` (same root cause as
-- 20260824_fix_handle_new_message_profiles_users_mismatch.sql)
-- ============================================================
-- `profiles` has 4 rows; the app's real, actively-maintained user
-- table (`users`) has 12 -- confirmed live. Found by grepping every
-- function in `public` referencing `profiles` after fixing
-- handle_new_message(). `users` has every column these functions need
-- (full_name, username, avatar_url, is_verified, following_count,
-- followers_count, posts_count -- confirmed via information_schema),
-- so this is a straightforward table-name swap for each:
--
-- handle_call_status_change(): notifications.body is NOT NULL, same
-- as notifications.title was for the messages bug -- a missed call
-- FROM any of the 8 affected users would crash this trigger and fail
-- the UPDATE that marks the call 'missed' at all. Same severity class
-- as the messages bug, just not yet reported.
--
-- handle_follow(): UPDATE ... WHERE id = <missing profiles row> just
-- silently matches zero rows (not an error) -- so follows themselves
-- were never blocked, but following_count/followers_count silently
-- never updated for any of the 8 affected users on either side of the
-- relationship.
--
-- handle_profile_post_count(): same silent-no-op class of bug as
-- handle_follow() -- posts_count never updated in `users` for any of
-- the 8 affected users' new posts (this already updated `profiles`,
-- not `users`, so it was updating the wrong -- and likely unread --
-- table the whole time regardless).
--
-- search_profiles(): not currently called anywhere in the app (dead
-- RPC), but would have silently failed to find 8 of the app's 12 real
-- users if ever wired up. Fixed for consistency/future-proofing.
--
-- Safe to run multiple times.
-- ============================================================

begin;

create or replace function public.handle_call_status_change()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
  IF NEW.status = 'missed' AND OLD.status = 'ringing' THEN
    PERFORM create_notification(
      NEW.receiver_id,
      'missed_call',
      'Missed ' || NEW.type || ' call',
      COALESCE((SELECT full_name FROM users WHERE id = NEW.caller_id), 'Someone'),
      NEW.caller_id,
      jsonb_build_object('conversation_id', NEW.conversation_id, 'call_id', NEW.id)
    );
  END IF;
  RETURN NULL;
END; $function$;

create or replace function public.handle_follow()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    UPDATE users SET followers_count = followers_count + 1 WHERE id = NEW.following_id;

    PERFORM create_notification(
      NEW.following_id,
      'community_join',
      'started following you',
      '',
      NEW.follower_id,
      '{}'::JSONB
    );

  ELSIF TG_OP = 'DELETE' THEN
    UPDATE users SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
    UPDATE users SET followers_count = GREATEST(followers_count - 1, 0) WHERE id = OLD.following_id;
  END IF;
  RETURN NULL;
END; $function$;

create or replace function public.handle_profile_post_count()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET posts_count = posts_count + 1 WHERE id = NEW.author_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.is_deleted AND NOT OLD.is_deleted THEN
    UPDATE users SET posts_count = GREATEST(posts_count - 1, 0) WHERE id = NEW.author_id;
  END IF;
  RETURN NULL;
END; $function$;

create or replace function public.search_profiles(query text)
returns table(id uuid, full_name text, username text, avatar_url text, is_verified boolean)
language sql
security definer
set search_path to 'public'
as $function$
  SELECT id, full_name, username, avatar_url, is_verified
  FROM users
  WHERE
    id <> auth.uid()
    AND (
      full_name ILIKE '%' || query || '%'
      OR username ILIKE '%' || query || '%'
    )
  ORDER BY
    CASE WHEN username ILIKE query || '%' THEN 0 ELSE 1 END,
    full_name
  LIMIT 20;
$function$;

commit;
