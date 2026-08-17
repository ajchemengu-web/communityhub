/// Cross-platform entry point for the New Post / New Reel route.
///
/// `new_post_screen.dart` (native) is built around `photo_manager`,
/// which has no Flutter Web implementation whatsoever — not degraded,
/// simply absent — and around `dart:io`, which fails to *compile* for
/// web regardless of any runtime (`kIsWeb`) branch. So app_router.dart
/// must never import new_post_screen.dart directly when building for
/// web; this conditional export swaps in new_post_screen_web.dart (a
/// separate, simpler picker built on image_picker, which does support
/// web) instead. Same pattern as video_compressor.dart.
library;

export 'new_post_route_web.dart' if (dart.library.io) 'new_post_route_io.dart';
