/// LiveKit — Live Streaming
///
/// The server URL is not sensitive (same category as the Supabase URL or
/// Stripe publishable key) — safe to ship in the client. The API
/// key/secret used to mint access tokens live only in the
/// `livekit-generate-token` Edge Function's environment.
class LiveKitConstants {
  // Replace with your LiveKit Cloud project URL (wss://your-project.livekit.cloud)
  static const String serverUrl = 'wss://REPLACE_ME.livekit.cloud';
}
