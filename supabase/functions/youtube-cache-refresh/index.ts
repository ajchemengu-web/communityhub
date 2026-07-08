// Populates `youtube_cache` on a schedule so end-user requests read from
// the cache (free) instead of hitting YouTube's Search API directly
// (100 calls/day total, shared across every user of the app — the app
// was hitting this ceiling almost immediately without a real cache).
//
// Budget: ~10 search.list calls per run (100 quota units each = ~1,000
// units), run twice a day via pg_cron → well under the 10,000-unit /
// 100-call daily ceiling, leaving headroom for the client's own live
// fallback when a specific hub's cache is thin.
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const YOUTUBE_API_KEY = Deno.env.get("YOUTUBE_API_KEY")!;
const YT_BASE = "https://www.googleapis.com/youtube/v3";

// Keyword lists mirrored from lib/core/constants/app_constants.dart —
// keep these two in sync if the app's keyword lists change.
const HUB_QUERIES: Record<string, string> = {
  faith: "gospel OR worship OR sermon",
  technology: "programming OR flutter OR cybersecurity",
  science: "science OR physics OR chemistry",
  languages: "language learning OR vocabulary OR grammar",
  career: "career advice OR job interview OR resume",
  biology: "biology OR cell biology OR genetics",
  computer_science: "computer science OR algorithms OR data structures",
  history: "history documentary OR ancient history",
  psychology: "psychology OR cognitive science OR mental health",
  english: "english grammar OR english vocabulary",
};

async function searchHub(hubType: string, query: string) {
  const url = `${YT_BASE}/search?part=snippet&q=${encodeURIComponent(query)}&type=video&maxResults=50&order=relevance&safeSearch=strict&key=${YOUTUBE_API_KEY}`;
  const res = await fetch(url);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`search failed for ${hubType}: ${res.status} ${body}`);
  }
  const json = await res.json();
  return (json.items ?? []) as any[];
}

async function fetchDetails(videoIds: string[]) {
  if (videoIds.length === 0) return new Map<string, any>();
  const url = `${YT_BASE}/videos?part=snippet,statistics,contentDetails&id=${videoIds.join(",")}&key=${YOUTUBE_API_KEY}`;
  const res = await fetch(url);
  if (!res.ok) return new Map<string, any>();
  const json = await res.json();
  const map = new Map<string, any>();
  for (const item of json.items ?? []) map.set(item.id, item);
  return map;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const results: Record<string, number | string> = {};
  let totalUpserted = 0;

  for (const [hubType, query] of Object.entries(HUB_QUERIES)) {
    try {
      const items = await searchHub(hubType, query);
      const videoIds = items
        .map((it) => it.id?.videoId)
        .filter((id): id is string => !!id);
      const details = await fetchDetails(videoIds);

      const rows = items
        .filter((it) => it.id?.videoId)
        .map((it) => {
          const id = it.id.videoId as string;
          const detail = details.get(id);
          const stats = detail?.statistics ?? {};
          return {
            youtube_id: id,
            title: it.snippet?.title ?? "",
            description: it.snippet?.description ?? "",
            channel_id: it.snippet?.channelId ?? "",
            channel_title: it.snippet?.channelTitle ?? "",
            thumbnail_url:
              it.snippet?.thumbnails?.high?.url ??
              it.snippet?.thumbnails?.default?.url ??
              "",
            hub_type: hubType,
            published_at: it.snippet?.publishedAt ?? null,
            view_count: stats.viewCount ? Number(stats.viewCount) : null,
            like_count: stats.likeCount ? Number(stats.likeCount) : null,
            duration: detail?.contentDetails?.duration ?? null,
            fetch_score: stats.viewCount ? Number(stats.viewCount) : 0,
            expires_at: new Date(
              Date.now() + 7 * 24 * 60 * 60 * 1000,
            ).toISOString(),
          };
        });

      if (rows.length > 0) {
        const { error } = await db
          .from("youtube_cache")
          .upsert(rows, { onConflict: "youtube_id" });
        if (error) throw error;
      }

      results[hubType] = rows.length;
      totalUpserted += rows.length;
    } catch (e) {
      results[hubType] = `error: ${(e as Error).message}`;
    }
  }

  return new Response(
    JSON.stringify({ totalUpserted, results }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
