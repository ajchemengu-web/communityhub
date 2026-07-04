CREATE TABLE IF NOT EXISTS public.conversations (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type                    TEXT NOT NULL DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
  name                    TEXT,
  cover_url               TEXT,
  last_message            TEXT,
  last_message_at         TIMESTAMPTZ,
  last_message_sender_id  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_by              UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.conversation_members (
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  last_read_at    TIMESTAMPTZ,
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id       UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content               TEXT,
  type                  TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text','image','video','audio','call_log','deleted')),
  media_url             TEXT,
  media_thumbnail_url   TEXT,
  reply_to_id           UUID REFERENCES public.messages(id) ON DELETE SET NULL,
  reactions             JSONB NOT NULL DEFAULT '{}',
  is_deleted            BOOLEAN NOT NULL DEFAULT FALSE,
  call_type             TEXT,
  call_duration         INTEGER,
  call_status           TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation
  ON public.messages(conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversation_members_user
  ON public.conversation_members(user_id);

CREATE TABLE IF NOT EXISTS public.calls (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  caller_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type            TEXT NOT NULL CHECK (type IN ('audio','video')),
  status          TEXT NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing','active','ended','missed','declined')),
  channel_name    TEXT NOT NULL,
  started_at      TIMESTAMPTZ,
  ended_at        TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view their conversations"
  ON public.conversations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = conversations.id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Members can create conversations"
  ON public.conversations FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Members can update conversations"
  ON public.conversations FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = conversations.id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Members can view conversation_members"
  ON public.conversation_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members cm
      WHERE cm.conversation_id = conversation_members.conversation_id
        AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can join conversations"
  ON public.conversation_members FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Members can update their own read status"
  ON public.conversation_members FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Members can view messages"
  ON public.messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = messages.conversation_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Members can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = messages.conversation_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Senders can update their messages"
  ON public.messages FOR UPDATE
  USING (sender_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = messages.conversation_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Call participants can view calls"
  ON public.calls FOR SELECT
  USING (caller_id = auth.uid() OR receiver_id = auth.uid());

CREATE POLICY "Callers can insert calls"
  ON public.calls FOR INSERT
  WITH CHECK (caller_id = auth.uid());

CREATE POLICY "Participants can update calls"
  ON public.calls FOR UPDATE
  USING (caller_id = auth.uid() OR receiver_id = auth.uid());

ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;

CREATE OR REPLACE FUNCTION get_direct_conversation(user_a UUID, user_b UUID)
RETURNS TABLE(id UUID) LANGUAGE sql STABLE AS $$
  SELECT c.id FROM public.conversations c
  JOIN public.conversation_members ma ON ma.conversation_id = c.id AND ma.user_id = user_a
  JOIN public.conversation_members mb ON mb.conversation_id = c.id AND mb.user_id = user_b
  WHERE c.type = 'direct'
  LIMIT 1;
$$;
