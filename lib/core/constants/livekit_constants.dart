/// LiveKit — Live Streaming & 1:1 Calls
///
/// The server URL is not sensitive (same category as the Supabase URL or
/// Stripe publishable key) — safe to ship in the client. The API
/// key/secret used to mint access tokens live only in the
/// `livekit-generate-token` Edge Function's environment.
class LiveKitConstants {
  /// CommunityDome's LiveKit Cloud project (project ID p_1lg2v5vxamx).
  static const String serverUrl = 'wss://communitydome-mwg1opsz.livekit.cloud';
}
