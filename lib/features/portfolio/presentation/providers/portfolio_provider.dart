import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/portfolio_repository.dart';

/// Whether [userId] has a published Profolio portfolio, and its URL if so
/// -- same lookup PortfolioScreen itself does for the "view someone
/// else's portfolio" case, exposed as a provider so the profile page can
/// use it to show a status-aware subtitle ("Your portfolio is live" vs.
/// "Create your professional portfolio") without the WebView screen ever
/// being opened. `autoDispose.family` keeps this cheap: each profile
/// visited gets its own cached lookup that's thrown away once nothing
/// is watching it anymore, rather than an ever-growing cache of every
/// profile ever viewed this session.
final publishedPortfolioUrlProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, userId) {
  return PortfolioRepository.instance.fetchPublishedPortfolioUrl(userId);
});
