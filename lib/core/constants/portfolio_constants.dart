/// Profolio — the separate, standalone portfolio site (Next.js on
/// Vercel + its own Supabase project) this integration links out to. See
/// lib/features/portfolio/ for the CommunityHub side of the integration
/// and supabase/functions/portfolio-handoff-token for the token-minting
/// half of the single-sign-on handoff.
class PortfolioConstants {
  /// Profolio's production URL. Not sensitive — same category as
  /// LiveKitConstants.serverUrl or the Supabase project URL below.
  ///
  /// REPLACE_ME: the profolio-web repo's own .env.local still has
  /// NEXT_PUBLIC_SITE_URL set to localhost (its local-dev value) — this
  /// needs the *real* deployed Vercel URL instead (e.g.
  /// https://profolio-web.vercel.app, or a custom domain once one's
  /// attached in Vercel). Find it on the Vercel dashboard's project page
  /// once profolio-web is deployed there.
  static const String baseUrl = 'https://profolio-sooty-two.vercel.app';

  /// Profolio's own Supabase project (completely separate from this
  /// app's — see .env.local in profolio-web). Used only for a public,
  /// RLS-scoped read: "does this CommunityHub user have a published
  /// portfolio, and what's its slug" — see
  /// PortfolioRepository.fetchPublishedPortfolioUrl. The anon/publishable
  /// key below is not a secret (that's the whole point of the anon key —
  /// same category as this app's own Supabase anon key); never put
  /// Profolio's service_role key here or anywhere in this Flutter app.
  static const String supabaseUrl = 'https://ronezbfegdpnsfvrawzk.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_bQtJB_drRemNuRDCHJn-cQ_0N9cB9ul';
}
