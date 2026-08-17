/// Cross-platform entry point for the in-app camera recorder route. See
/// new_post_route.dart for why this indirection is necessary — the
/// native screen imports dart:io + the `camera` package, both
/// unavailable on web, and an unconditional import would break the web
/// build's compile step regardless of any runtime branch.
library;

export 'camera_route_web.dart' if (dart.library.io) 'camera_route_io.dart';
