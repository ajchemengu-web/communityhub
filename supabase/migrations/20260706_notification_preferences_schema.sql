-- ── Notification Preferences ─────────────────────────────────────
-- Per-category opt-out. A missing row (user never visited the
-- settings screen) is treated as "everything on" by the app —
-- these columns default TRUE so a freshly-inserted row matches that
-- same default explicitly once the user does visit the screen.

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id     UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  likes       BOOLEAN NOT NULL DEFAULT TRUE,
  comments    BOOLEAN NOT NULL DEFAULT TRUE,
  follows     BOOLEAN NOT NULL DEFAULT TRUE,
  messages    BOOLEAN NOT NULL DEFAULT TRUE,
  events      BOOLEAN NOT NULL DEFAULT TRUE,
  communities BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own notification preferences"
  ON public.notification_preferences FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can manage their own notification preferences"
  ON public.notification_preferences FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.set_notification_preferences_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_preferences_updated_at ON public.notification_preferences;
CREATE TRIGGER trg_notification_preferences_updated_at
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION public.set_notification_preferences_updated_at();
