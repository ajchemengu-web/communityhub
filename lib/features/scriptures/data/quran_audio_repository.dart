import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:audioplayers/audioplayers.dart'
    show Source, BytesSource, DeviceFileSource;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';

/// Metadata for a Quran reciter, sourced from alquran.cloud's audio
/// edition directory (https://alquran.cloud/api).
class ReciterModel {
  const ReciterModel({required this.id, required this.name});

  /// alquran.cloud audio edition identifier, e.g. "ar.alafasy". This is
  /// also the path segment cdn.islamic.network expects.
  final String id;

  final String name;
}

/// Resolves Quran audio for the Scriptures screen — a single continuous
/// whole-surah recitation (see [surahAudioUrl]/[surahAudioSource]) rather
/// than per-verse clips. Per-verse playback was removed along with the
/// Kiswahili full-narration feature it was built alongside; with no
/// Kiswahili audio to interleave, chaining individually-fetched verse
/// clips just added network-hop gaps between verses for no benefit over
/// one continuous file.
class QuranAudioRepository {
  QuranAudioRepository._() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.alquran.cloud/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  static final QuranAudioRepository instance = QuranAudioRepository._();

  late final Dio _dio;

  static const String _surahAudioCdnBase =
      'https://cdn.islamic.network/quran/audio-surah';

  /// Web-only. `audioplayers`' web backend sets `crossOrigin="anonymous"`
  /// on every `<audio>` element it creates — unconditionally, with no
  /// public option to turn it off (see bluefireteam/audioplayers's
  /// wrapped_player.dart; it's there to support stereo-panning). That
  /// makes the browser require an `Access-Control-Allow-Origin` header
  /// on the audio response, which cdn.islamic.network doesn't send. This
  /// is exactly what broke Quran playback on the web build: the browser
  /// console showed "Access to audio ... has been blocked by CORS
  /// policy". Plays back fine as a plain browser navigation, and on
  /// mobile there's no CORS concept at all — this only bites the web
  /// build specifically.
  ///
  /// Routes web playback through a Supabase Edge Function
  /// (quran-audio-proxy) that fetches the same bytes server-side and
  /// relays them with CORS headers attached. Mobile keeps hitting the
  /// CDN directly — no reason to add a network hop where it isn't
  /// needed.
  static const String _webProxyBase =
      '${AppConstants.supabaseUrl}/functions/v1/quran-audio-proxy';

  static const String arabicRecitationAttribution =
      'Arabic recitation audio courtesy of alquran.cloud / '
      'cdn.islamic.network.';

  /// Small curated set of reciters with confirmed whole-surah audio,
  /// used until (or unless) [fetchReciters] can reach the live
  /// directory. These three match the app's previous curated list
  /// (Alafasy, Husary, Al-Akhdar) so switching audio providers is
  /// invisible to anyone who already picked one of them.
  static const List<ReciterModel> fallbackReciters = [
    ReciterModel(id: 'ar.alafasy', name: 'Mishary Alafasy'),
    ReciterModel(id: 'ar.husary', name: 'Mahmoud Khalil Al-Hussary'),
    ReciterModel(id: 'ar.ibrahimakhbar', name: 'Ibrahim Al-Akhdar'),
  ];

  /// Fetches the full reciter directory from alquran.cloud. Falls back
  /// to [fallbackReciters] on any network/parse error, or if the
  /// response shape ever changes — the player should never be left with
  /// zero reciters to choose from.
  Future<List<ReciterModel>> fetchReciters() async {
    try {
      final response = await _dio.get('/edition', queryParameters: {
        'format': 'audio',
        'language': 'ar',
      });
      final raw = response.data['data'] as List<dynamic>? ?? [];

      final reciters = <ReciterModel>[];
      for (final r in raw) {
        final edition = Map<String, dynamic>.from(r as Map);
        final id = edition['identifier'] as String?;
        final name = edition['englishName'] as String?;
        if (id == null || name == null) continue;
        reciters.add(ReciterModel(id: id, name: name));
      }

      return reciters.isNotEmpty ? reciters : fallbackReciters;
    } catch (_) {
      // Offline, API shape changed, or request failed — the feature
      // still works with the bundled fallback list.
      return fallbackReciters;
    }
  }

  /// Builds the whole-surah recitation URL for [reciter].
  String surahAudioUrl(ReciterModel reciter, int surahNumber,
      {int bitrate = 128}) {
    if (kIsWeb) {
      return Uri.parse(_webProxyBase).replace(queryParameters: {
        'type': 'full_surah',
        'bitrate': '$bitrate',
        'reciter': reciter.id,
        'surah': '$surahNumber',
        'apikey': AppConstants.supabaseAnonKey,
      }).toString();
    }
    return '$_surahAudioCdnBase/$bitrate/${reciter.id}/$surahNumber.mp3';
  }

  /// Resolves [surahAudioUrl] into a ready-to-play [Source].
  ///
  /// Web: a plain `<audio>` element has no way to attach a custom
  /// header, so this fetches the bytes itself via dio (which can) and
  /// hands the player an in-memory [BytesSource] — see the class-level
  /// comment on why a query-string apikey alone isn't enough against
  /// this project's Supabase gateway.
  ///
  /// Mobile: whole-surah files are large enough (tens of MB for longer
  /// surahs) that Android's native MediaPlayer HTTP streamer hits a
  /// mid-stream ProtocolException on this CDN and never starts playback
  /// (confirmed live: NuCachedSource2 error -1010 -> MEDIA_ERROR_UNKNOWN)
  /// — the same file streams fine as a plain browser download, so it's
  /// specifically the native streaming path that chokes on it. Per-verse
  /// clips never hit this because they're small enough to finish before
  /// it triggers. Downloading first and playing the local file sidesteps
  /// it entirely; the download is cached by surah+reciter so replaying
  /// or switching back to an already-fetched combination is instant.
  Future<Source> surahAudioSource(ReciterModel reciter, int surahNumber,
      {int bitrate = 128}) async {
    final url = surahAudioUrl(reciter, surahNumber, bitrate: bitrate);
    if (kIsWeb) return BytesSource(await _fetchProxiedBytes(url));

    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/quran_surah_${reciter.id}_$surahNumber.mp3');
    if (await file.exists() && await file.length() > 0) {
      return DeviceFileSource(file.path);
    }
    try {
      await Dio().download(url, file.path);
    } catch (e) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return DeviceFileSource(file.path);
  }

  Future<Uint8List> _fetchProxiedBytes(String url) async {
    final response = await Dio().get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'apikey': AppConstants.supabaseAnonKey},
      ),
    );
    return Uint8List.fromList(response.data ?? const []);
  }
}
