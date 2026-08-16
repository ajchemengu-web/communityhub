import 'dart:typed_data';

/// Web stub — `v_video_compressor` is a native (Android/iOS) plugin with
/// no browser implementation, so on web compression is skipped entirely
/// and the original bytes are uploaded as-is. Selected via conditional
/// export in video_compressor.dart (`if (dart.library.io)` swaps this
/// out for video_compressor_io.dart on platforms that have dart:io).
Future<Uint8List> compressVideoBytes(Uint8List bytes) async => bytes;
