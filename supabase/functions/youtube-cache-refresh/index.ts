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

// Queries mirrored from lib/core/constants/app_constants.dart +
// YouTubeService._buildHubQuery — keep these two in sync if the app's
// keyword lists or query-building logic change.
//
// Each entry is: the hub's first 3 keywords (only the first 3 ever drive
// the real query — see techKeywords'/languagesKeywords' comments in
// app_constants.dart) joined with YouTube's actual OR operator '|' (NOT
// the literal word 'OR', which YouTube treats as a plain search term, not
// a boolean operator — that was a real bug here), followed by
// AppConstants.generalContentExclusions (applied to every hub), followed
// by AppConstants.academicDepthQuery for hubs in AppConstants.stemHubTypes
// only.
const GENERAL_EXCLUSIONS = "-baby -toddler -nursery";
const ACADEMIC_DEPTH = "university lecture advanced research -kids -cartoon";

// Hard content-safety block list -- mirrors AppConstants.kidsContentBlockTerms
// in lib/core/constants/app_constants.dart. Unlike GENERAL_EXCLUSIONS (a
// soft `-word` query hint YouTube's popularity-driven relevance ranking
// can and does override for a sufficiently viral channel -- confirmed
// live: a toddler-education channel with billions of views defeated
// `-baby -toddler -nursery` and still got cached, then won the #1 slot
// on the app's home-feed "All" tab, which reads every hub's cached
// videos together sorted by raw view count with no hub filter at all),
// this is enforced as an actual drop BEFORE anything reaches the cache
// -- once a video like that is cached, no per-hub query change can stop
// it from dominating "All". Keep in sync with the Dart list.
const KIDS_CONTENT_BLOCK_TERMS = [
  "baby", "babies", "toddler", "infant", "infants",
  "nursery rhyme", "nursery rhymes", "lullaby", "lullabies",
  "preschool", "pre-school", "kindergarten", "peekaboo",
  "ms rachel", "songs for littles", "cocomelon", "baby shark",
  "first words", "learning video for babies", "kids learning video",
  // Kids/children content channels don't always use "baby"/"toddler"
  // wording -- e.g. "Jack Hartmann Kids Music Channel" (363M views)
  // and "Adi Connection"'s "Kids English Words & Vocabulary" both
  // slipped past the terms above on a live cache refresh.
  "kids", "children's", "for children", "kindergarteners",
];

function isKidsContent(title: string, description: string, channelTitle: string): boolean {
  const text = `${title} ${description} ${channelTitle}`.toLowerCase();
  return KIDS_CONTENT_BLOCK_TERMS.some((term) => text.includes(term));
}

const HUB_QUERIES: Record<string, string> = {
  faith: `gospel|worship|sermon ${GENERAL_EXCLUSIONS}`,
  technology: `programming|software engineering|cybersecurity ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  // Engineering used to just ride along inside the generic `technology`
  // query above (whose keywords never mention engineering at all) — now
  // gets its own dedicated, academically-biased query, matching the app.
  engineering: `engineering|mechanical engineering|civil engineering ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  science: `biology|chemistry|physics ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  languages: `foreign language course|language learning for adults|polyglot ${GENERAL_EXCLUSIONS}`,
  career: `programming|software engineering|cybersecurity ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  biology: `biology|cell biology|genetics ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  computer_science: `computer science|algorithms|data structures ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  history: `history|ancient history|world war ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  psychology: `psychology|cognitive psychology|behavioral psychology ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  english: `learn english|english lesson|english grammar ${GENERAL_EXCLUSIONS}`,
  // These 6 STEM sub-hubs had no dedicated query at all -- they either
  // showed nothing but stale/empty cache, or fell through to the
  // client's own live per-user fallback, which is quota-costly and (for
  // Robotics specifically) meant the sub-hub's cache was never being
  // warmed by the cron job in the first place. All six mirror their
  // app_constants.dart keyword list's first 3 entries + the same
  // academic-depth bias as the other STEM hubs above, so university/
  // research-level material displaces generic explainer content here
  // too instead of only in the hubs that happened to already have an
  // entry.
  chemistry: `chemistry|organic chemistry|periodic table ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  physics: `physics|quantum mechanics|relativity ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  mathematics: `mathematics|algebra|calculus ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  geography: `geography|physical geography|human geography ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  robotics: `robotics|automation|robot ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
  aviation: `aviation|aeronautics|pilot ${GENERAL_EXCLUSIONS} ${ACADEMIC_DEPTH}`,
};

// Confirmed live that ACADEMIC_DEPTH's keyword bias alone does NOT keep
// Shorts/meme content out (a real backfill still surfaced "Periodic
// Table Song" and #shorts clips ahead of any lecture content for the
// chemistry hub) -- YouTube's relevance ranking is fundamentally
// popularity-driven and doesn't treat trailing query text as a hard
// filter. videoDuration=long is an actual API-level filter: university
// lectures/research talks are almost always >20min, while the junk
// polluting these hubs is almost always Shorts/clips. Applied to every
// hub now, not just STEM -- the exact video that prompted this (a viral
// toddler-education channel surfacing in the Languages hub) was 60
// minutes long, so duration alone wouldn't have caught it either; see
// KIDS_CONTENT_BLOCK_TERMS above for the filter that actually did.
async function searchHub(hubType: string, query: string) {
  const url = `${YT_BASE}/search?part=snippet&q=${encodeURIComponent(query)}&type=video&maxResults=50&order=relevance&safeSearch=strict&videoDuration=long&key=${YOUTUBE_API_KEY}`;
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

  // Scheduled cron invocations send no body (or an empty one), which
  // covers every hub -- `hubs` is only ever passed explicitly for a
  // deliberate one-off backfill of specific hubs (e.g. warming a newly
  // added hub's cache without re-spending quota on the other ones that
  // are already populated).
  let hubFilter: string[] | null = null;
  try {
    const body = await req.json();
    if (Array.isArray(body?.hubs) && body.hubs.length > 0) {
      hubFilter = body.hubs;
    }
  } catch {
    // no/invalid JSON body -- keep default (all hubs)
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const results: Record<string, number | string> = {};
  let totalUpserted = 0;

  const hubEntries = hubFilter
    ? Object.entries(HUB_QUERIES).filter(([hubType]) => hubFilter!.includes(hubType))
    : Object.entries(HUB_QUERIES);

  for (const [hubType, query] of hubEntries) {
    try {
      const items = await searchHub(hubType, query);
      const videoIds = items
        .map((it) => it.id?.videoId)
        .filter((id): id is string => !!id);
      const details = await fetchDetails(videoIds);

      const rows = items
        .filter((it) => it.id?.videoId)
        .filter((it) =>
          !isKidsContent(
            it.snippet?.title ?? "",
            it.snippet?.description ?? "",
            it.snippet?.channelTitle ?? "",
          )
        )
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
