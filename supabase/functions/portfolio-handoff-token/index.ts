// Mints a short-lived, signed handoff token so a CommunityHub user can be
// silently signed into their linked Profolio account (a completely
// separate app + separate Supabase project: github.com/.../profolio-web,
// hosted on Vercel) without ever seeing a second login screen.
//
// Same "mint server-side, verify server-side" shape as
// livekit-generate-token, but the verifier lives in the OTHER app
// (profolio-web's app/api/auth/communityhub/route.ts) rather than in
// this project, since the two apps don't share a database or an auth
// system to check a session against directly.
//
// Token shape: `<base64url(payload json)>.<base64url(HMAC-SHA256 sig)>`
// -- a hand-rolled minimal JWT-alike rather than a real JWT library,
// matching profolio-web's existing "plain Node crypto, no extra auth
// dependency" style (see its lib/security.ts). Both sides must agree on
// this exact format; see the matching comment in that route.ts.
//
// SECURITY: PORTFOLIO_HANDOFF_SECRET must be set as a secret on this
// Edge Function (`supabase secrets set PORTFOLIO_HANDOFF_SECRET=...` or
// via the dashboard) AND as the *same* value in profolio-web's Vercel
// env vars (COMMUNITYHUB_HANDOFF_SECRET). Anyone who has this secret can
// mint a token claiming to be any CommunityHub user, so treat it exactly
// like the LiveKit/Stripe/Paystack secrets already in this functions
// folder -- never in client code, never logged.

import { corsHeaders } from "../_shared/cors.ts";
import { anonClient, requireUserId } from "../_shared/payments.ts";

const HANDOFF_SECRET = Deno.env.get("PORTFOLIO_HANDOFF_SECRET")!;
const TOKEN_LIFETIME_SECONDS = 120; // short window: this is a one-shot
// "log me in" handoff consumed within seconds of being minted (the
// Flutter side opens the WebView immediately after fetching it), not a
// credential meant to survive being copied around.

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmacSha256(secret: string, message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return new Uint8Array(sig);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!HANDOFF_SECRET) {
      throw new Error("PORTFOLIO_HANDOFF_SECRET is not configured on this function");
    }

    const anon = anonClient();
    const authHeader = req.headers.get("Authorization") ?? "";
    const bearerToken = authHeader.replace("Bearer ", "");

    // requireUserId() alone only returns the id; grab the full user object
    // here too so we can read the verified email off it directly instead
    // of re-querying — Supabase Auth's getUser() already gives us that.
    const { data, error } = await anon.auth.getUser(bearerToken);
    if (error || !data.user) throw new Error("Unauthorized");
    const chUserId = data.user.id;
    const email = data.user.email;
    if (!email) {
      // Every CommunityHub account is created via email/password (see
      // RegisterScreen), so this should be unreachable in practice --
      // failing closed rather than minting a token Profolio can't use
      // to provision an account (it requires an email).
      throw new Error("Your CommunityHub account has no email on file");
    }

    // full_name/avatar_url are best-effort personalization for the new
    // Profolio profile Profolio auto-provisions on first handoff -- not
    // required for the handoff itself to work, so a lookup failure here
    // shouldn't block signing in.
    let fullName: string | null = null;
    let avatarUrl: string | null = null;
    try {
      const { data: userRow } = await anon
        .from("users")
        .select("full_name, avatar_url")
        .eq("id", chUserId)
        .maybeSingle();
      fullName = (userRow?.full_name as string | undefined) ?? null;
      avatarUrl = (userRow?.avatar_url as string | undefined) ?? null;
    } catch {
      // best-effort, see above
    }

    const now = Math.floor(Date.now() / 1000);
    const payload = {
      chUserId,
      email,
      fullName,
      avatarUrl,
      iat: now,
      exp: now + TOKEN_LIFETIME_SECONDS,
    };

    const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
    const sigBytes = await hmacSha256(HANDOFF_SECRET, payloadB64);
    const sigB64 = base64UrlEncode(sigBytes);
    const token = `${payloadB64}.${sigB64}`;

    return new Response(JSON.stringify({ token }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
