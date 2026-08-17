import 'dart:typed_data' show Uint8List;

import 'package:audioplayers/audioplayers.dart' show Source, UrlSource, BytesSource;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/constants/app_constants.dart';

/// Metadata for a Quran reciter, sourced from alquran.cloud's audio
/// edition directory (https://alquran.cloud/api) — the same provider
/// this feature already uses for per-ayah Arabic/English/Kiswahili text
/// (see quran_screen.dart's `_fetch()`). Using one provider for both
/// text and audio means every reciter here is guaranteed to expose true
/// per-ayah (verse-by-verse) audio files, not just whole-surah files —
/// required for the verse-by-verse playback this screen does.
class ReciterModel {
  const ReciterModel({required this.id, required this.name});

  /// alquran.cloud audio edition identifier, e.g. "ar.alafasy". This is
  /// also the path segment cdn.islamic.network expects.
  final String id;

  final String name;
}

/// Resolves Quran audio for the Scriptures screen.
///
/// Arabic recitation is per-ayah (per-verse), streamed directly from
/// alquran.cloud's audio CDN (cdn.islamic.network) using the reciter's
/// "versebyverse" edition identifier. This app previously sourced
/// Arabic audio from mp3quran.net, which only publishes whole-surah
/// files — fine for "play the whole surah" but unable to support
/// verse-by-verse playback, which is what this screen needs.
///
/// There is no human-recorded Kiswahili translation *audio* per verse
/// published anywhere (confirmed) — only whole-surah narrations exist,
/// from the Internet Archive / VideoQuran.net. This used to also offer a
/// per-verse mode that read the translation aloud via on-device
/// text-to-speech, interleaved right after each Arabic verse. That was
/// removed: a synthesized voice reading scripture doesn't sound right to
/// many listeners — several described it as uncomfortably robotic and
/// mispronounced, and for East African Kiswahili speakers in particular
/// it read as clearly artificial rather than a respectful recitation.
/// The human-recorded VideoQuran.net track is the only Kiswahili option
/// now: it plays once, after all the Arabic verses finish (no per-verse
/// timestamps exist in that recording, so it can't be interleaved
/// per-verse the way the removed TTS mode was). See quran_screen.dart's
/// `_playFullNarration`.
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

  static const String _audioCdnBase =
      'https://cdn.islamic.network/quran/audio';

  static const String _swahiliTranslationBase =
      'https://archive.org/download/'
      'TranslationOfTheMeaningsOfTheNobleQuranInSwahilikiswahilimp3';

  /// Web-only. `audioplayers`' web backend sets `crossOrigin="anonymous"`
  /// on every `<audio>` element it creates — unconditionally, with no
  /// public option to turn it off (see bluefireteam/audioplayers's
  /// wrapped_player.dart; it's there to support stereo-panning). That
  /// makes the browser require an `Access-Control-Allow-Origin` header
  /// on the audio response, which neither cdn.islamic.network nor
  /// archive.org send. This is exactly what broke Quran playback on the
  /// web build: the browser console showed "Access to audio ... has been
  /// blocked by CORS policy" for the Arabic CDN, and the Kiswahili
  /// narration would have hit the identical wall the first time anyone
  /// played a surah through to the end, since it comes from a different
  /// host with the same missing header. Both play back fine as a plain
  /// browser navigation, and on mobile there's no CORS concept at all —
  /// this only bites the web build specifically.
  ///
  /// Routes web playback through a Supabase Edge Function
  /// (quran-audio-proxy) that fetches the same bytes server-side and
  /// relays them with CORS headers attached. Mobile keeps hitting the
  /// CDNs directly — no reason to add a network hop where it isn't
  /// needed.
  static const String _webProxyBase =
      '${AppConstants.supabaseUrl}/functions/v1/quran-audio-proxy';

  static const String arabicRecitationAttribution =
      'Arabic recitation audio courtesy of alquran.cloud / '
      'cdn.islamic.network.';

  /// Attribution required by the full-narration Kiswahili audio's
  /// Creative Commons "Attribution-NonCommercial-NoDerivatives" license.
  /// Shown whenever that track plays.
  static const String swahiliTranslationLicenseNote =
      'Kiswahili full narration: VideoQuran.net, via the Internet '
      'Archive — CC BY-NC-ND 3.0. Streamed, not redistributed.';

  /// Small curated set of reciters with confirmed per-ayah audio, used
  /// until (or unless) [fetchReciters] can reach the live directory.
  /// These three match the app's previous curated list (Alafasy,
  /// Husary, Al-Akhdar) so switching audio providers is invisible to
  /// anyone who already picked one of them.
  static const List<ReciterModel> fallbackReciters = [
    ReciterModel(id: 'ar.alafasy', name: 'Mishary Alafasy'),
    ReciterModel(id: 'ar.husary', name: 'Mahmoud Khalil Al-Hussary'),
    ReciterModel(id: 'ar.ibrahimakhbar', name: 'Ibrahim Al-Akhdar'),
  ];

  /// Fetches the full per-ayah reciter directory from alquran.cloud.
  /// Falls back to [fallbackReciters] on any network/parse error, or if
  /// the response shape ever changes — the player should never be left
  /// with zero reciters to choose from.
  Future<List<ReciterModel>> fetchReciters() async {
    try {
      final response = await _dio.get('/edition', queryParameters: {
        'format': 'audio',
        'language': 'ar',
        'type': 'versebyverse',
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

  /// Builds the per-ayah recitation URL for [reciter] and a
  /// QURAN-WIDE ayah number (1..6236 — NOT the in-surah verse number).
  /// See the 'globalNumber' field populated in quran_screen.dart's
  /// `_fetch()`, taken from alquran.cloud's ayah `number` field (as
  /// opposed to `numberInSurah`).
  String arabicAyahAudioUrl(ReciterModel reciter, int globalAyahNumber,
      {int bitrate = 128}) {
    if (kIsWeb) {
      return Uri.parse(_webProxyBase).replace(queryParameters: {
        'type': 'arabic',
        'bitrate': '$bitrate',
        'reciter': reciter.id,
        'ayah': '$globalAyahNumber',
        'apikey': AppConstants.supabaseAnonKey,
      }).toString();
    }
    return '$_audioCdnBase/$bitrate/${reciter.id}/$globalAyahNumber.mp3';
  }

  /// The whole-surah, human-narrated Kiswahili translation track (see
  /// class doc) — used by "full narration" mode.
  String swahiliTranslationAudioUrl(int surahNumber) {
    if (kIsWeb) {
      return Uri.parse(_webProxyBase).replace(queryParameters: {
        'type': 'kiswahili',
        'surah': '$surahNumber',
        'apikey': AppConstants.supabaseAnonKey,
      }).toString();
    }
    final padded = surahNumber.toString().padLeft(3, '0');
    return '$_swahiliTranslationBase/'
        '${padded}VideoQuran.Net-Swahili-Kiswahili-Translation.mp3';
  }

  // ── Web playback sources ──────────────────────────────────
  //
  // A plain `<audio>` element (what `UrlSource` becomes under the hood
  // on Flutter web) has no way to attach a custom header to the
  // request it makes -- that's a browser limitation on media elements,
  // not something audioplayers or this app controls. The proxy URLs
  // above work around the *CORS* problem by putting the Supabase
  // anon key in the `?apikey=` query string instead of a header. That
  // used to be enough, but this project's Supabase gateway (confirmed
  // directly via the Edge Functions dashboard's "Test" tool: the same
  // key as a query param gets 401 "Invalid credentials", the identical
  // key as a header gets 200) only honors `apikey` when it's a header.
  //
  // So on web, fetch the audio bytes ourselves with dio (which *can*
  // set a header) and hand the player an in-memory [BytesSource]
  // instead of a URL at all. Native platforms never went through the
  // proxy in the first place (see arabicAyahAudioUrl/
  // swahiliTranslationAudioUrl above) and keep using [UrlSource]
  // unchanged.

  /// Resolves [arabicAyahAudioUrl] into a ready-to-play [Source].
  Future<Source> arabicAyahAudioSource(
      ReciterModel reciter, int globalAyahNumber,
      {int bitrate = 128}) async {
    final url =
        arabicAyahAudioUrl(reciter, globalAyahNumber, bitrate: bitrate);
    if (!kIsWeb) return UrlSource(url);
    return BytesSource(await _fetchProxiedBytes(url));
  }

  /// Resolves [swahiliTranslationAudioUrl] into a ready-to-play [Source].
  Future<Source> swahiliTranslationAudioSource(int surahNumber) async {
    final url = swahiliTranslationAudioUrl(surahNumber);
    if (!kIsWeb) return UrlSource(url);
    return BytesSource(await _fetchProxiedBytes(url));
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
