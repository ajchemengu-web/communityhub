import 'package:dio/dio.dart';

import '../../../core/constants/portfolio_constants.dart';
import '../../../core/services/supabase_service.dart';

class PortfolioRepository {
  PortfolioRepository._();
  static final instance = PortfolioRepository._();

  /// Calls the `portfolio-handoff-token` Edge Function (this app's own
  /// Supabase project) to mint a short-lived signed token proving who
  /// the current CommunityHub user is, then builds the URL that logs
  /// them straight into their linked Profolio account -- auto-provisioned
  /// on first visit if they don't have one yet -- with no second login
  /// screen. See that function's source for exactly what it signs, and
  /// profolio-web's app/api/auth/communityhub/route.ts for how it's
  /// verified and exchanged for a real Profolio session.
  Future<String> fetchOwnPortfolioUrl() async {
    final res = await SupabaseService.client.functions
        .invoke('portfolio-handoff-token');
    final data = res.data as Map<String, dynamic>;
    final token = data['token'] as String;
    return '${PortfolioConstants.baseUrl}/api/auth/communityhub'
        '?token=$token&next=/dashboard';
  }

  /// Whether [userId] has a *published* portfolio, and if so, the URL to
  /// view it -- read directly from Profolio's own Supabase project via
  /// its public anon-key REST API. No handoff token involved: this is
  /// the exact same public row Profolio's own /portfolio/<slug> page
  /// reads, gated by Profolio's "public can read published profiles" RLS
  /// policy on its side, not by anything CommunityHub enforces. Returns
  /// null if they have no linked Profolio account, or have one but
  /// haven't published it -- either way there's nothing public to show.
  Future<String?> fetchPublishedPortfolioUrl(String userId) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: PortfolioConstants.supabaseUrl,
        headers: {
          'apikey': PortfolioConstants.supabaseAnonKey,
          'Authorization': 'Bearer ${PortfolioConstants.supabaseAnonKey}',
        },
      ));
      final res = await dio.get('/rest/v1/profiles', queryParameters: {
        'community_hub_user_id': 'eq.$userId',
        'is_published': 'eq.true',
        'select': 'slug',
        'limit': '1',
      });
      final rows = res.data as List;
      if (rows.isEmpty) return null;
      final slug = (rows.first as Map)['slug'] as String?;
      if (slug == null) return null;
      return '${PortfolioConstants.baseUrl}/portfolio/$slug';
    } catch (_) {
      // Network hiccup or Profolio unreachable -- treat the same as "no
      // published portfolio" rather than surfacing a raw error for what
      // is, from the visitor's point of view, an optional profile
      // section.
      return null;
    }
  }
}
