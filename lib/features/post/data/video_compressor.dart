/// Cross-platform video-bytes compression entry point.
///
/// `dart:io` causes a Flutter Web COMPILE-TIME failure for any file that
/// imports it, regardless of runtime (`kIsWeb`) branching — the import
/// alone pulls it into the compiled program graph. Dart's conditional
/// export solves this: on platforms with `dart:io` available, the real
/// (temp-file-based) implementation is used; on web, a no-op stub that
/// never references dart:io is used instead.
library;

export 'video_compressor_stub.dart'
    if (dart.library.io) 'video_compressor_io.dart';
