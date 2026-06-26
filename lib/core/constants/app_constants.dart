/// CommunityHub — App Constants

abstract class AppConstants {
  // ── App Info ──────────────────────────────────────────────
  static const String appName = 'CommunityHub';
  static const String appTagline = 'Faith meets Tech';
  static const String appVersion = '1.0.0';

  // ── Supabase ──────────────────────────────────────────────
  static const String supabaseUrl = 'https://uxfxrvyamfgnjggjbrkh.supabase.co';
  // NOTE: Real anon key loaded from .env at runtime via flutter_dotenv
  // This is the public publishable key — safe to be in source
  static const String supabaseAnonKey =
      'sb_publishable_pVUqM-iEvlVP8sYQE8BEmQ_1dFfDmvA';

  // ── YouTube ───────────────────────────────────────────────
  static const String youtubeBaseUrl =
      'https://www.googleapis.com/youtube/v3';
  static const int youtubeMaxResults = 20;

  // ── Content Filter Tags ───────────────────────────────────
  /// Keywords used to filter YouTube content for the Faith Hub
  static const List<String> faithKeywords = [
    'gospel', 'worship', 'sermon', 'christian', 'praise',
    'bible', 'prayer', 'church', 'hymn', 'devotion',
    'scripture', 'jesus', 'holy spirit', 'faith', 'ministry',
  ];

  /// Keywords used to filter YouTube content for the Career Hub
  static const List<String> techKeywords = [
    'programming', 'flutter', 'cybersecurity', 'data science',
    'machine learning', 'coding', 'software engineering',
    'web development', 'python', 'javascript', 'networking',
    'cloud computing', 'artificial intelligence', 'devops',
  ];

  // ── Feed ──────────────────────────────────────────────────
  static const int feedPageSize = 15;
  static const int searchPageSize = 20;
  static const int reelsPageSize = 10;
  static const int commentsPageSize = 20;

  // ── Media Limits ──────────────────────────────────────────
  static const int maxPostImages = 10;
  static const int maxVideoSizeMb = 100;
  static const int maxImageSizeMb = 10;
  static const int maxBioLength = 150;
  static const int maxCaptionLength = 2200;
  static const int maxCommentLength = 500;
  static const int maxChatMessageLength = 1000;
  static const int maxCommunityNameLength = 60;
  static const int maxAnnouncementLength = 1000;

  // ── Story ─────────────────────────────────────────────────
  static const int storyDurationHours = 24;
  static const int storyDisplaySeconds = 5; // per story item

  // ── Notification Types ────────────────────────────────────
  static const String notifLike = 'like';
  static const String notifComment = 'comment';
  static const String notifFollow = 'follow';
  static const String notifMention = 'mention';
  static const String notifMessage = 'message';
  static const String notifNewLogin = 'new_login';
  static const String notifProfileView = 'profile_view';
  static const String notifCommunityInvite = 'community_invite';
  static const String notifAnnouncement = 'announcement';

  // ── Community Roles ───────────────────────────────────────
  static const String roleAdmin = 'admin';
  static const String roleModerator = 'moderator';
  static const String roleMember = 'member';

  // ── Content Status ────────────────────────────────────────
  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusFlagged = 'flagged';

  // ── Hub Types ─────────────────────────────────────────────
  static const String hubFaith = 'faith';
  static const String hubCareer = 'career';
  static const String hubAll = 'all';

  // ── Cache Duration ────────────────────────────────────────
  static const Duration youtubeCacheDuration = Duration(hours: 6);
  static const Duration feedCacheDuration = Duration(minutes: 5);

  // ── Animation Durations ───────────────────────────────────
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 350);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // ── Supabase Table Names ──────────────────────────────────
  static const String tableUsers = 'users';
  static const String tablePosts = 'posts';
  static const String tableReels = 'reels';
  static const String tableStories = 'stories';
  static const String tableFollows = 'follows';
  static const String tableLikes = 'likes';
  static const String tableComments = 'comments';
  static const String tableNotifications = 'notifications';
  static const String tableCommunities = 'communities';
  static const String tableCommunityMembers = 'community_members';
  static const String tableAnnouncements = 'announcements';
  static const String tableChats = 'chats';
  static const String tableChatMessages = 'chat_messages';
  static const String tableYoutubeCache = 'youtube_cache';
  static const String tableContentFlags = 'content_flags';
  static const String tableAds = 'ads';

  // ── Supabase Storage Buckets ──────────────────────────────
  static const String bucketAvatars = 'avatars';
  static const String bucketPostMedia = 'post_media';
  static const String bucketReelMedia = 'reel_media';
  static const String bucketStoryMedia = 'story_media';
  static const String bucketChatMedia = 'chat_media';
  static const String bucketCommunityCovers = 'community_covers';
}
