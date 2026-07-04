CREATE TABLE IF NOT EXISTS public.live_streams (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  channel_name  TEXT NOT NULL UNIQUE,
  title         TEXT NOT NULL DEFAULT 'Live',
  hub_type      TEXT,
  viewer_count  INTEGER NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.live_stream_comments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id  UUID NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content    TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_streams_active
  ON public.live_streams(is_active, viewer_count DESC);

CREATE INDEX IF NOT EXISTS idx_live_comments_stream
  ON public.live_stream_comments(stream_id, created_at ASC);

ALTER TABLE public.live_streams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.live_stream_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active streams"
  ON public.live_streams FOR SELECT
  USING (TRUE);

CREATE POLICY "Hosts can create streams"
  ON public.live_streams FOR INSERT
  WITH CHECK (host_id = auth.uid());

CREATE POLICY "Hosts can update their streams"
  ON public.live_streams FOR UPDATE
  USING (host_id = auth.uid());

CREATE POLICY "Anyone can view comments"
  ON public.live_stream_comments FOR SELECT
  USING (TRUE);

CREATE POLICY "Authenticated users can comment"
  ON public.live_stream_comments FOR INSERT
  WITH CHECK (user_id = auth.uid());

ALTER PUBLICATION supabase_realtime ADD TABLE public.live_streams;
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_stream_comments;

CREATE OR REPLACE FUNCTION increment_stream_viewers(stream_id UUID)
RETURNS void LANGUAGE sql AS $$
  UPDATE public.live_streams
  SET viewer_count = viewer_count + 1
  WHERE id = stream_id AND is_active = TRUE;
$$;

CREATE OR REPLACE FUNCTION decrement_stream_viewers(stream_id UUID)
RETURNS void LANGUAGE sql AS $$
  UPDATE public.live_streams
  SET viewer_count = GREATEST(viewer_count - 1, 0)
  WHERE id = stream_id AND is_active = TRUE;
$$;
