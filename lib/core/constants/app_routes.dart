/// CommunityHub — Named Route Paths
library;

abstract class AppRoutes {
  // ── Auth ──────────────────────────────────────────────────
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String setupProfile = '/setup-profile';

  // ── Main Shell (Bottom Nav) ───────────────────────────────
  static const String shell = '/shell';
  static const String home = '/shell/home';
  static const String search = '/shell/search';
  static const String newPost = '/shell/new-post';
  static const String reels = '/shell/reels';
  static const String updates = '/shell/updates';
  static const String profile = '/shell/profile';

  // ── Social ────────────────────────────────────────────────
  static const String postDetail = '/post/:postId';
  static const String reelDetail = '/reel/:reelId';
  static const String userProfile = '/user/:userId';
  static const String editProfile = '/edit-profile';
  static const String followers = '/user/:userId/followers';
  static const String following = '/user/:userId/following';
  static const String comments = '/post/:postId/comments';

  // ── Communities ───────────────────────────────────────────
  static const String communities = '/communities';
  static const String communityDetail = '/community/:communityId';
  static const String communityMembers = '/community/:communityId/members';
  static const String createCommunity = '/communities/create';
  static const String myChurch = '/my-church';
  static const String communityAnnouncements = '/community/:communityId/announcements';
  static const String groupDetail = '/community/:communityId/group/:groupId';

  // ── Chat ──────────────────────────────────────────────────
  static const String chats = '/chats';
  static const String chatDetail = '/chat/:chatId';
  static const String newChat = '/chats/new';
  static const String stories = '/stories/:userId';
  static const String callScreen = '/call/:callId';

  // ── Notifications ─────────────────────────────────────────
  static const String notifications = '/notifications';

  // ── Events ────────────────────────────────────────────────
  static const String events = '/events';
  static const String createEvent = '/events/create';
  static const String eventDetail = '/events/:eventId';

  // ── YouTube / Content ─────────────────────────────────────
  static const String videoPlayer = '/video/:videoId';
  static const String faithHub = '/faith-hub';
  static const String careerHub = '/career-hub';

  // ── Live & Camera ─────────────────────────────────────
  static const String liveStart = '/live/start';
  static const String liveWatch = '/live/:streamId/watch';
  static const String cameraRecorder = '/camera/record';

  // ── Giving ────────────────────────────────────────────────
  static const String give = '/give';
  static const String givingHistory = '/give/history';

  // ── Marketplace ───────────────────────────────────────────
  static const String marketplace = '/marketplace';
  static const String createProduct = '/marketplace/create';
  static const String productDetail = '/marketplace/:productId';
  static const String sellerOrders = '/marketplace/orders';

  // ── Shops ─────────────────────────────────────────────────
  static const String manageShop = '/shop/manage';
  /// The seller dashboard (Overview/Listings/Orders/Settings). Optionally
  /// takes a `?tab=` query param -- see ShopAdminScreen.initialTab and
  /// app_router.dart's builder for the accepted values.
  static const String shopAdmin = '/shop/admin';
  static const String shop = '/shop/:ownerId';

  // ── Portfolio (Profolio integration) ───────────────────────
  static const String myPortfolio = '/portfolio';
  static const String viewPortfolio = '/portfolio/:userId';

  // ── Memberships ───────────────────────────────────────────
  static const String tierPicker = '/community/:communityId/memberships';
  static const String mySubscriptions = '/memberships';

  // ── Settings ─────────────────────────────────────────────
  static const String settings = '/settings';
  static const String privacySettings = '/settings/privacy';
  static const String notificationSettings = '/settings/notifications';
  static const String accountSettings = '/settings/account';
  static const String helpCenter = '/help';
  static const String about = '/about';
}
