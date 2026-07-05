/// CommunityHub — App Constants
library;

abstract class AppConstants {
  // ── App Info ──────────────────────────────────────────────
  static const String appName = 'CommunityHub';
  static const String appTagline = 'Faith, Knowledge & Community';
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
  static const String youtubeApiKey = 'AIzaSyCK4ck3x6NFEH02Djdr440noBH2MULGW2o';

  // ── Payments ──────────────────────────────────────────────
  // Publishable/public keys only — safe to ship in the client.
  // Secret keys live in Supabase Edge Function env vars, never here.
  static const String stripePublishableKey = 'pk_test_REPLACE_ME';
  static const String paystackPublicKey = 'pk_test_REPLACE_ME';

  // ── Ads (AdMob) ───────────────────────────────────────────
  // These are Google's public TEST ad unit ids — safe to ship while
  // developing, but MUST be swapped for real ones before release
  // (the App IDs in AndroidManifest.xml / Info.plist too).
  static const String admobAndroidBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String admobIosBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';
  // Number of feed posts / reels between each inserted ad slot.
  static const int adFrequency = 6;

  // ── Content Filter Keywords ───────────────────────────────

  // Faith (multi-religion umbrella — Christianity + Islam + general)
  static const List<String> faithKeywords = [
    // Christianity
    'gospel', 'worship', 'sermon', 'christian', 'praise',
    'bible', 'prayer', 'church', 'hymn', 'devotion',
    'scripture', 'jesus', 'holy spirit', 'faith', 'ministry',
    'evangelism', 'testimony', 'discipleship', 'baptism',
    // Islam
    'quran', 'hadith', 'mosque', 'salah', 'islamic', 'allah',
    'ramadan', 'eid', 'prophet muhammad', 'sunnah', 'dua',
    'tafsir', 'fiqh', 'halal', 'hijab', 'dawah', 'masjid',
    'jummah', 'umrah', 'hajj', 'zakat', 'shahada', 'iman',
    'nasheed', 'islamic lecture', 'quran recitation', 'sheikh',
    // General spirituality
    'spirituality', 'faith community', 'religion', 'meditation',
  ];

  // Christianity-specific sub-hub
  static const List<String> christianityKeywords = [
    'gospel', 'worship', 'sermon', 'christian', 'praise',
    'bible', 'prayer', 'church', 'hymn', 'devotion',
    'scripture', 'jesus', 'holy spirit', 'ministry', 'evangelism',
    'testimony', 'discipleship', 'baptism', 'pentecostal', 'catholic',
    'protestant', 'salvation', 'cross', 'resurrection', 'grace',
  ];

  // Islam-specific sub-hub
  static const List<String> islamKeywords = [
    'quran', 'hadith', 'mosque', 'salah', 'islamic', 'allah',
    'ramadan', 'eid', 'prophet muhammad', 'sunnah', 'dua',
    'tafsir', 'fiqh', 'halal', 'hijab', 'dawah', 'masjid',
    'jummah', 'umrah', 'hajj', 'zakat', 'shahada', 'iman',
    'nasheed', 'islamic lecture', 'quran recitation', 'sheikh',
    'imam', 'wudu', 'adhan', 'bismillah', 'alhamdulillah', 'masha allah',
  ];

  // Technology / Career
  static const List<String> techKeywords = [
    'programming', 'flutter', 'cybersecurity', 'data science',
    'machine learning', 'coding', 'software engineering',
    'web development', 'python', 'javascript', 'networking',
    'cloud computing', 'artificial intelligence', 'devops',
  ];

  // Sciences
  static const List<String> scienceKeywords = [
    'biology', 'chemistry', 'physics', 'mathematics', 'science',
    'psychology', 'geography', 'history', 'anatomy', 'ecology',
    'geology', 'astronomy', 'neuroscience', 'genetics',
  ];
  static const List<String> biologyKeywords = [
    'biology', 'cell biology', 'genetics', 'ecology', 'anatomy',
    'microbiology', 'botany', 'zoology', 'evolution', 'biochemistry',
  ];
  static const List<String> chemistryKeywords = [
    'chemistry', 'organic chemistry', 'periodic table', 'chemical reaction',
    'molecular', 'atom', 'electron', 'titration', 'thermodynamics',
  ];
  static const List<String> physicsKeywords = [
    'physics', 'quantum mechanics', 'relativity', 'thermodynamics',
    'electromagnetism', 'optics', 'mechanics', 'nuclear physics', 'astrophysics',
  ];
  static const List<String> mathematicsKeywords = [
    'mathematics', 'algebra', 'calculus', 'geometry', 'statistics',
    'trigonometry', 'linear algebra', 'differential equations', 'number theory',
  ];
  static const List<String> psychologyKeywords = [
    'psychology', 'cognitive psychology', 'behavioral psychology',
    'neuroscience', 'mental health', 'psychiatry', 'therapy', 'mindset',
  ];
  static const List<String> geographyKeywords = [
    'geography', 'physical geography', 'human geography', 'cartography',
    'climate', 'geopolitics', 'urban planning', 'population', 'continent',
  ];
  static const List<String> historyKeywords = [
    'history', 'ancient history', 'world war', 'civilisation', 'historical',
    'archaeology', 'empire', 'revolution', 'medieval', 'colonial',
  ];

  // Technology sub-hubs
  static const List<String> engineeringKeywords = [
    'engineering', 'mechanical engineering', 'civil engineering',
    'electrical engineering', 'chemical engineering', 'structural engineering',
    'thermodynamics', 'materials science',
  ];
  static const List<String> roboticsKeywords = [
    'robotics', 'automation', 'robot', 'arduino', 'raspberry pi',
    'mechatronics', 'sensors', 'actuators', 'control systems', 'AI robot',
  ];
  static const List<String> aviationKeywords = [
    'aviation', 'aeronautics', 'pilot', 'aircraft', 'aerospace',
    'flight training', 'aerodynamics', 'cockpit', 'navigation', 'drone',
  ];
  static const List<String> computerScienceKeywords = [
    'computer science', 'algorithms', 'data structures', 'operating systems',
    'compiler', 'networking', 'database', 'cybersecurity', 'software engineering',
  ];

  // Languages
  static const List<String> languagesKeywords = [
    'language learning', 'french', 'english', 'spanish', 'german',
    'swahili', 'chinese', 'japanese', 'arabic', 'linguistics', 'grammar',
  ];
  static const List<String> frenchKeywords = [
    'learn french', 'french lesson', 'français', 'grammaire française',
    'french grammar', 'french vocabulary', 'parler français',
  ];
  static const List<String> englishKeywords = [
    'learn english', 'english lesson', 'english grammar', 'english speaking',
    'IELTS', 'TOEFL', 'english vocabulary', 'pronunciation',
  ];
  static const List<String> spanishKeywords = [
    'learn spanish', 'español', 'spanish lesson', 'gramática española',
    'spanish vocabulary', 'hablar español',
  ];
  static const List<String> germanKeywords = [
    'learn german', 'deutsch', 'german lesson', 'deutsche Grammatik',
    'german vocabulary', 'Deutsch lernen',
  ];
  static const List<String> swahiliKeywords = [
    'learn swahili', 'kiswahili', 'swahili lesson', 'swahili grammar',
    'swahili vocabulary', 'speak swahili',
  ];
  static const List<String> chineseKeywords = [
    'learn chinese', 'mandarin', 'chinese lesson', 'HSK', 'putonghua',
    '普通话', 'chinese vocabulary', 'chinese characters',
  ];
  static const List<String> japaneseKeywords = [
    'learn japanese', 'nihongo', 'japanese lesson', 'JLPT', 'hiragana',
    'katakana', 'kanji', '日本語', 'japanese vocabulary',
  ];
  static const List<String> arabicKeywords = [
    'learn arabic', 'arabic lesson', 'عربي', 'arabic grammar',
    'arabic vocabulary', 'classical arabic', 'modern standard arabic',
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
  static const String notifFollowRequest = 'follow_request';
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
  // Main tabs
  static const String hubAll = 'all';
  static const String hubFaith = 'faith';
  static const String hubScience = 'science';
  static const String hubTechnology = 'technology';
  static const String hubLanguages = 'languages';

  // Legacy alias kept for DB backwards-compat
  static const String hubCareer = 'career';

  // Faith sub-hubs
  static const String hubChristianity = 'christianity';
  static const String hubIslam = 'islam';

  // Science sub-hubs
  static const String hubBiology = 'biology';
  static const String hubChemistry = 'chemistry';
  static const String hubPhysics = 'physics';
  static const String hubMathematics = 'mathematics';
  static const String hubPsychology = 'psychology';
  static const String hubGeography = 'geography';
  static const String hubHistory = 'history';

  // Technology sub-hubs
  static const String hubEngineering = 'engineering';
  static const String hubRobotics = 'robotics';
  static const String hubAviation = 'aviation';
  static const String hubComputerScience = 'computer_science';

  // Language sub-hubs
  static const String hubFrench = 'french';
  static const String hubEnglish = 'english';
  static const String hubSpanish = 'spanish';
  static const String hubGerman = 'german';
  static const String hubSwahili = 'swahili';
  static const String hubChinese = 'chinese';
  static const String hubJapanese = 'japanese';
  static const String hubArabic = 'arabic';

  /// Faith sub-hubs
  static const List<String> faithSubHubs = [
    hubChristianity, hubIslam,
  ];

  /// All sub-hubs that belong to the Sciences main tab
  static const List<String> scienceSubHubs = [
    hubBiology, hubChemistry, hubPhysics, hubMathematics,
    hubPsychology, hubGeography, hubHistory,
  ];

  /// All sub-hubs that belong to the Technology main tab
  static const List<String> technologySubHubs = [
    hubEngineering, hubRobotics, hubAviation, hubComputerScience,
    hubCareer, // includes legacy career/tech posts
  ];

  /// All sub-hubs that belong to the Languages main tab
  static const List<String> languageSubHubs = [
    hubFrench, hubEnglish, hubSpanish, hubGerman,
    hubSwahili, hubChinese, hubJapanese, hubArabic,
  ];

  /// Returns the keyword list for a given hub type
  static List<String> keywordsFor(String hubType) {
    switch (hubType) {
      case hubFaith:          return faithKeywords;
      case hubChristianity:   return christianityKeywords;
      case hubIslam:          return islamKeywords;
      case hubScience:        return scienceKeywords;
      case hubBiology:        return biologyKeywords;
      case hubChemistry:      return chemistryKeywords;
      case hubPhysics:        return physicsKeywords;
      case hubMathematics:    return mathematicsKeywords;
      case hubPsychology:     return psychologyKeywords;
      case hubGeography:      return geographyKeywords;
      case hubHistory:        return historyKeywords;
      case hubTechnology:
      case hubCareer:         return techKeywords;
      case hubEngineering:    return engineeringKeywords;
      case hubRobotics:       return roboticsKeywords;
      case hubAviation:       return aviationKeywords;
      case hubComputerScience: return computerScienceKeywords;
      case hubLanguages:      return languagesKeywords;
      case hubFrench:         return frenchKeywords;
      case hubEnglish:        return englishKeywords;
      case hubSpanish:        return spanishKeywords;
      case hubGerman:         return germanKeywords;
      case hubSwahili:        return swahiliKeywords;
      case hubChinese:        return chineseKeywords;
      case hubJapanese:       return japaneseKeywords;
      case hubArabic:         return arabicKeywords;
      default:                return [];
    }
  }

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
  static const String tableUserBlocks = 'user_blocks';
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
  static const String tablePaymentTransactions = 'payment_transactions';

  // ── Supabase Storage Buckets ──────────────────────────────
  static const String bucketAvatars = 'avatars';
  static const String bucketPostMedia = 'post_media';
  static const String bucketReelMedia = 'reel_media';
  static const String bucketStoryMedia = 'story_media';
  static const String bucketChatMedia = 'chat_media';
  static const String bucketCommunityCovers = 'community_covers';
  static const String bucketProductImages = 'product_images';
}
