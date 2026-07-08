-- ── Scheduled YouTube Cache Refresh ───────────────────────────────
-- `youtube_cache` existed in the schema from the start but nothing ever
-- populated it, so every video request — from every user — was hitting
-- YouTube's Search API directly. That API has a hard ceiling of 100
-- search.list calls per day, shared across the entire app (not
-- per-user), and the app's own front-loaded pagination (built to fix
-- Reels'/Home's scroll walls) was burning through that in a handful of
-- requests, which would exhaust the shared daily quota for everyone.
--
-- This schedules the `youtube-cache-refresh` Edge Function twice a day
-- (~10 search calls per run, well under the daily ceiling) to
-- pre-populate the cache. Real user requests then read from
-- `youtube_cache` for free — no quota cost per request — and the
-- client's own live-API pagination only kicks in as a fallback when a
-- given hub's cache is thin.
--
-- NOTE: this migration documents cron jobs already created directly
-- against the live database (via the Management API, same as several
-- other migrations this session) — running it again is a harmless
-- no-op since cron.schedule() with the same job name just reschedules.

SELECT cron.schedule(
  'youtube-cache-refresh-morning',
  '0 6 * * *',
  $$
  SELECT net.http_post(
    url := 'https://uxfxrvyamfgnjggjbrkh.supabase.co/functions/v1/youtube-cache-refresh',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
  $$
);

SELECT cron.schedule(
  'youtube-cache-refresh-evening',
  '0 18 * * *',
  $$
  SELECT net.http_post(
    url := 'https://uxfxrvyamfgnjggjbrkh.supabase.co/functions/v1/youtube-cache-refresh',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
  $$
);
