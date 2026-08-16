import 'package:dio/dio.dart';

/// Metadata for a Quran reciter, sourced from mp3quran.net.
class ReciterModel {
  const ReciterModel({
    required this.id,
    required this.name,
    required this.serverUrl,
  });

  /// Reciter id — matches mp3quran.net's numeric `id` where the entry
  /// came from the live API, or a stable short code for bundled entries.
  final String id;

  final String name;

  /// Base URL of the reciter's audio server, ending in '/'.
  /// e.g. https://server8.mp3quran.net/afs/
  final String serverUrl;

  /// Builds the full-surah recitation URL for [surahNumber] (1..114).
  String surahAudioUrl(int surahNumber) =>
      '$serverUrl${surahNumber.toString().padLeft(3, '0')}.mp3';

  factory ReciterModel.fromMp3QuranJson(
      Map<String, dynamic> reciter, Map<String, dynamic> moshaf) {
    return ReciterModel(
      id: '${reciter['id']}',
      name: reciter['name'] as String? ?? 'Unknown reciter',
      serverUrl: moshaf['server'] as String,
    );
  }
}

/// Resolves Quran audio for the Scriptures screen: Arabic recitation
/// (per-surah, from mp3quran.net) and a Swahili translation narration
/// (per-surah, from the Internet Archive). Both tracks are streamed
/// directly from their host CDN — nothing is downloaded, re-hosted, or
/// modified by this app.
class QuranAudioRepository {
  QuranAudioRepository._() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://www.mp3quran.net/api/v3',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  static final QuranAudioRepository instance = QuranAudioRepository._();

  late final Dio _dio;

  static const String _swahiliTranslationBase =
      'https://archive.org/download/'
      'TranslationOfTheMeaningsOfTheNobleQuranInSwahilikiswahilimp3';

  /// Attribution required by the Swahili translation audio's Creative
  /// Commons "Attribution-NonCommercial-NoDerivatives" license. Shown
  /// wherever that track plays.
  static const String swahiliTranslationLicenseNote =
      'Swahili translation audio: VideoQuran.net, via the Internet '
      'Archive — CC BY-NC-ND 3.0. Streamed, not redistributed.';

  static const String arabicRecitationAttribution =
      'Arabic recitation audio courtesy of mp3quran.net.';

  /// Small curated set of well-known reciters, used until (or unless)
  /// [fetchReciters] can reach the live mp3quran.net directory. Verified
  /// server URLs as of this feature's build.
  static const List<ReciterModel> fallbackReciters = [
    ReciterModel(
      id: '123',
      name: 'Mishary Alafasy',
      serverUrl: 'https://server8.mp3quran.net/afs/',
    ),
    ReciterModel(
      id: '118',
      name: 'Mahmoud Khalil Al-Hussary',
      serverUrl: 'https://server13.mp3quran.net/husr/',
    ),
    ReciterModel(
      id: '1',
      name: 'Ibrahim Al-Akhdar',
      serverUrl: 'https://server6.mp3quran.net/akdr/',
    ),
  ];

  /// Fetches the full reciter directory from mp3quran.net. Falls back to
  /// [fallbackReciters] on any network/parse error, or if the response
  /// shape ever changes — the player should never be left with zero
  /// reciters to choose from.
  Future<List<ReciterModel>> fetchReciters() async {
    try {
      final response =
          await _dio.get('/reciters', queryParameters: {'language': 'eng'});
      final raw = response.data['reciters'] as List<dynamic>? ?? [];

      final reciters = <ReciterModel>[];
      for (final r in raw) {
        final reciter = Map<String, dynamic>.from(r as Map);
        final moshafList = reciter['moshaf'] as List<dynamic>? ?? [];
        if (moshafList.isEmpty) continue;
        final moshafMaps =
            moshafList.map((m) => Map<String, dynamic>.from(m as Map)).toList();
        // mp3quran.net doesn't guarantee the standard "Hafs A'n Assem"
        // riwaya (the transmission almost every reciter records and every
        // listener expects) is listed first when a reciter has recorded
        // more than one. Blindly taking moshafList.first broke playback
        // for Mishary Alafasy (id 123) in particular: his array lists a
        // rare "Rewayat AlDorai A'n Al-Kisa'ai" riwaya first, and that
        // server folder doesn't actually have surah 1 (likely most/all
        // surahs) — it 404s. That surfaced in the app as a misleading
        // "Could not play audio. Check your internet connection." error,
        // even though the network and the standard Hafs URL both work
        // fine (confirmed by hand). Prefer the Hafs riwaya by name; fall
        // back to the first entry only if a reciter genuinely has none.
        final moshaf = moshafMaps.firstWhere(
          (m) => (m['name'] as String? ?? '').toLowerCase().contains('hafs'),
          orElse: () => moshafMaps.first,
        );
        if (moshaf['server'] == null) continue;
        reciters.add(ReciterModel.fromMp3QuranJson(reciter, moshaf));
      }

      return reciters.isNotEmpty ? reciters : fallbackReciters;
    } catch (_) {
      // Offline, API shape changed, or request failed — the feature
      // still works with the bundled fallback list.
      return fallbackReciters;
    }
  }

  String arabicSurahAudioUrl(ReciterModel reciter, int surahNumber) =>
      reciter.surahAudioUrl(surahNumber);

  String swahiliTranslationAudioUrl(int surahNumber) {
    final padded = surahNumber.toString().padLeft(3, '0');
    return '$_swahiliTranslationBase/'
        '${padded}VideoQuran.Net-Swahili-Kiswahili-Translation.mp3';
  }
}
