import 'package:dio/dio.dart';

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
/// from the Internet Archive / VideoQuran.net. Two Kiswahili modes are
/// offered because neither option is strictly better:
/// - Per-verse: on-device text-to-speech reads that verse's translation
///   text right after each Arabic verse — true per-verse pacing, but a
///   synthetic voice (quality/accent depends on the listener's device;
///   several users found it uncomfortably robotic/mispronounced).
/// - Full narration: the original human-recorded VideoQuran.net track,
///   much better voice quality, but can only play as one block for the
///   whole surah (no per-verse timestamps exist in that recording), so
///   it plays once after all the Arabic verses finish rather than
///   interleaved per verse.
/// See quran_screen.dart's `_speakKiswahiliForAyah` (per-verse) and
/// `_playFullNarration` (whole-surah), and the `_kiswahiliMode` toggle
/// that lets the user pick between them.
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

  static const String arabicRecitationAttribution =
      'Arabic recitation audio courtesy of alquran.cloud / '
      'cdn.islamic.network.';

  /// Shown in per-verse Kiswahili mode, since it's synthesized speech,
  /// not a human recording — the user should know that, and that
  /// quality/voice availability depends on their device.
  static const String kiswahiliTranslationNote =
      "Kiswahili translation is read aloud by your device's built-in "
      'text-to-speech, from the Ali Muhsin Al-Barwani Kiswahili '
      'translation text — no human-recorded per-verse Kiswahili audio '
      'exists to stream. Voice availability depends on your device.';

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
          {int bitrate = 128}) =>
      '$_audioCdnBase/$bitrate/${reciter.id}/$globalAyahNumber.mp3';

  /// The whole-surah, human-narrated Kiswahili translation track (see
  /// class doc) — used by "full narration" mode.
  String swahiliTranslationAudioUrl(int surahNumber) {
    final padded = surahNumber.toString().padLeft(3, '0');
    return '$_swahiliTranslationBase/'
        '${padded}VideoQuran.Net-Swahili-Kiswahili-Translation.mp3';
  }
}
