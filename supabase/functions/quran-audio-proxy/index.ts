// Proxies Quran audio for the WEB build only (see quran_audio_repository.dart
// for the full explanation — short version: audioplayers' web backend
// requires CORS headers that neither cdn.islamic.network nor archive.org
// send, which broke playback on the deployed web app; native/mobile hits
// those CDNs directly and never needed this).
//
// Deliberately NOT a general-purpose URL proxy — it only ever fetches from
// two hardcoded, allowlisted hosts, built from validated path segments, so
// this can't be turned into an open proxy for arbitrary URLs.
//
// corsHeaders is inlined here (other functions in this repo import it from
// ../_shared/cors.ts) so this file is a single self-contained paste if
// you're deploying through the Supabase Dashboard's function editor rather
// than the CLI — no need to also recreate the _shared folder there.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, range",
};

// Per-verse ("arabic") and Kiswahili full-narration audio proxying were
// removed along with per-verse playback and the Kiswahili feature in the
// app -- this now only ever proxies whole-surah recitation audio.
const AUDIO_SURAH_CDN = "https://cdn.islamic.network/quran/audio-surah";

const RECITER_PATTERN = /^[a-z0-9.]+$/i;
const DIGITS_PATTERN = /^\d+$/;

function badRequest(message: string) {
  return new Response(message, { status: 400, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const type = url.searchParams.get("type");

  let upstreamUrl: string;

  if (type === "full_surah") {
    const bitrate = url.searchParams.get("bitrate") ?? "128";
    const reciter = url.searchParams.get("reciter") ?? "";
    const surah = url.searchParams.get("surah") ?? "";

    if (
      !DIGITS_PATTERN.test(bitrate) ||
      !RECITER_PATTERN.test(reciter) ||
      !DIGITS_PATTERN.test(surah)
    ) {
      return badRequest("Invalid full_surah audio parameters");
    }

    upstreamUrl = `${AUDIO_SURAH_CDN}/${bitrate}/${reciter}/${surah}.mp3`;
  } else {
    return badRequest("Unknown or missing 'type' parameter");
  }

  // Forward Range so seeking still works — without this every seek
  // would re-download from byte zero instead of jumping to a position.
  const upstreamHeaders: Record<string, string> = {};
  const range = req.headers.get("range");
  if (range) upstreamHeaders["range"] = range;

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(upstreamUrl, { headers: upstreamHeaders });
  } catch (e) {
    return new Response(`Failed to reach upstream audio host: ${(e as Error).message}`, {
      status: 502,
      headers: corsHeaders,
    });
  }

  const headers = new Headers(corsHeaders);
  headers.set(
    "Content-Type",
    upstreamRes.headers.get("content-type") ?? "audio/mpeg",
  );
  const contentLength = upstreamRes.headers.get("content-length");
  if (contentLength) headers.set("Content-Length", contentLength);
  const contentRange = upstreamRes.headers.get("content-range");
  if (contentRange) headers.set("Content-Range", contentRange);
  headers.set("Accept-Ranges", upstreamRes.headers.get("accept-ranges") ?? "bytes");
  // Quran recitation audio never changes — safe to cache aggressively,
  // both in the browser and on any CDN in front of this function. Cuts
  // down on repeat invocations for the same ayah across users.
  headers.set("Cache-Control", "public, max-age=604800, immutable");

  return new Response(upstreamRes.body, {
    status: upstreamRes.status,
    headers,
  });
});
