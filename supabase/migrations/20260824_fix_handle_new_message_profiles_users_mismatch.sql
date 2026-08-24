-- ============================================================
-- Fix handle_new_message() reading from the wrong (legacy, mostly-
-- abandoned) `profiles` table instead of `users`
-- ============================================================
-- handle_new_message() -- the AFTER INSERT trigger on `messages` that
-- creates a "X sent you a message" notification for the recipient --
-- looked up the sender's display name via:
--   SELECT full_name INTO v_sender_name FROM profiles WHERE id = NEW.sender_id;
--
-- `profiles` is a stale legacy table with only 4 rows, while the app's
-- real, actively-maintained user table (`users`, referenced by every
-- other feature in this app -- posts, comments, chat, communities...)
-- has 12. Confirmed live: any user who exists in `users` but not in
-- `profiles` (8 of the current 12) produces v_sender_name = NULL, and
-- NULL || ' sent you a message' is NULL, which then hits
-- notifications.title's NOT NULL constraint -- crashing the entire
-- trigger, which crashes the entire message INSERT transaction. In
-- other words: any of those 8 users could NEVER successfully send a
-- single message to anyone, silently, with no error surfaced beyond
-- "new row violates ... constraint" three PL/pgSQL frames down.
--
-- Confirmed reproducible by simulating the exact INSERT as an affected
-- real user (monah_yvy) via `set local request.jwt.claims` -- got the
-- exact "null value in column title" error, tracing through
-- create_notification() <- handle_new_message() <- this INSERT.
--
-- Fix: read from `users` instead, with a defensive COALESCE fallback
-- so a genuinely missing name degrades to a generic notification
-- rather than breaking the send outright.
-- ============================================================

begin;

create or replace function public.handle_new_message()
returns trigger
language plpgsql
security definer
as $function$
DECLARE
  r RECORD;
  v_sender_name TEXT;
BEGIN
  IF NEW.type = 'call_log' THEN RETURN NULL; END IF;

  SELECT COALESCE(full_name, username, 'Someone') INTO v_sender_name
  FROM users WHERE id = NEW.sender_id;
  v_sender_name := COALESCE(v_sender_name, 'Someone');

  FOR r IN
    SELECT user_id FROM conversation_members
    WHERE conversation_id = NEW.conversation_id
      AND user_id <> NEW.sender_id
  LOOP
    PERFORM create_notification(
      r.user_id,
      'message',
      v_sender_name || ' sent you a message',
      CASE
        WHEN NEW.type = 'image' THEN 'Photo'
        WHEN NEW.type = 'video' THEN 'Video'
        WHEN NEW.type = 'audio' THEN 'Voice message'
        ELSE COALESCE(LEFT(NEW.content, 80), '')
      END,
      NEW.sender_id,
      jsonb_build_object('conversation_id', NEW.conversation_id)
    );
  END LOOP;

  UPDATE conversations
  SET
    last_message           = CASE
                               WHEN NEW.type = 'image' THEN 'Photo'
                               WHEN NEW.type = 'video' THEN 'Video'
                               WHEN NEW.type = 'audio' THEN 'Voice message'
                               ELSE NEW.content
                             END,
    last_message_at        = NEW.created_at,
    last_message_sender_id = NEW.sender_id
  WHERE id = NEW.conversation_id;

  RETURN NULL;
END; $function$;

commit;
