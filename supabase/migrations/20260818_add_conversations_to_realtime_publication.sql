-- 20240703_chat_schema.sql already had a line adding `conversations` to
-- the supabase_realtime publication alongside `messages`, but only
-- `messages` actually ended up in the live publication -- confirmed via
-- `select * from pg_publication_tables where pubname = 'supabase_realtime'`,
-- which listed messages, calls, donations, live_stream_comments,
-- live_streams, notifications, payment_transactions, but not
-- conversations. Re-adding it here, idempotently.
--
-- Not the cause of the "real-time messaging isn't working" report (the
-- chat list derives its live preview updates from `messages` INSERT
-- events directly, not from `conversations` changes -- see
-- ChatsNotifier._subscribeToNewMessages in chats_provider.dart), but a
-- real gap worth closing since other conversation-level realtime use
-- cases (e.g. live group name/avatar updates) would silently not work
-- without it.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  END IF;
END $$;
