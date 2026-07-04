// Mints a LiveKit access token server-side using the API key/secret
// (secrets — never in the Flutter app), same principle already applied
// to Stripe/Paystack/M-Pesa. `roomName` reuses the existing
// `live_streams.channel_name` column — LiveKit's "room" is the same
// concept as the channel/room abstraction that field already models.

import { AccessToken } from "npm:livekit-server-sdk@2";
import { corsHeaders } from "../_shared/cors.ts";
import { anonClient, requireUserId } from "../_shared/payments.ts";

const LIVEKIT_API_KEY = Deno.env.get("LIVEKIT_API_KEY")!;
const LIVEKIT_API_SECRET = Deno.env.get("LIVEKIT_API_SECRET")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await requireUserId(req, anonClient());
    const { roomName, role } = await req.json();

    if (!roomName || (role !== "host" && role !== "viewer")) {
      throw new Error("roomName and role ('host' | 'viewer') are required");
    }

    const token = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity: userId,
    });
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: role === "host",
      canSubscribe: true,
      canPublishData: true, // lets hosts and viewers send live chat/reactions over LiveKit data channels if needed later
    });

    return new Response(JSON.stringify({ token: await token.toJwt() }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
