import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:v_video_compressor/v_video_compressor.dart';

/// Native (Android/iOS/desktop) implementation. `v_video_compressor` only
/// operates on file paths, so this round-trips the bytes through a temp
/// file. Falls back to the original bytes if compression fails for any
/// reason — this should never block a post. Selected via conditional
/// export in video_compressor.dart; never imported on web (which would
/// fail to compile since this file uses dart:io).
Future<Uint8List> compressVideoBytes(Uint8List bytes) async {
  File? tempIn;
  File? tempOut;
  try {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    tempIn = File('${dir.path}/upload_in_$stamp.mp4');
    await tempIn.writeAsBytes(bytes);

    final result = await VVideoCompressor().compressVideo(
      tempIn.path,
      const VVideoCompressionConfig.medium(),
    );
    if (result == null) return bytes;

    tempOut = File(result.compressedFilePath);
    return await tempOut.readAsBytes();
  } catch (_) {
    return bytes;
  } finally {
    try {
      if (tempIn != null && await tempIn.exists()) await tempIn.delete();
    } catch (_) {}
    try {
      if (tempOut != null && await tempOut.exists()) await tempOut.delete();
    } catch (_) {}
  }
}
