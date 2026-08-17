/// Cross-platform entry point for the story-creation route. See
/// new_post_route.dart for why this indirection is necessary.
library;

export 'story_route_web.dart' if (dart.library.io) 'story_route_io.dart';
