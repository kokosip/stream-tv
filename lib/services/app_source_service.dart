import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSourceService {
  static const String _keySource = "app_active_source";

  static const String SOURCE_MOVIEBOX = "moviebox";
  static const String SOURCE_FOURKHDHUB = "4khdhub";
  static const String SOURCE_DRAMACHI = "dramachi";
  static const String SOURCE_PUSATFILM = "pusatfilm";
  static const String SOURCE_JURAGANFILM = "juraganfilm";
  static const String SOURCE_SAMEHADAKU = "samehadaku";
  static const String SOURCE_OTAKUDESU = "otakudesu";
  static const String SOURCE_ANICHIN = "anichin";
  static const String SOURCE_DRACINSI = "dracinsi";
  static const String SOURCE_DRAKORKITA = "drakorkita";
  static const String SOURCE_SORASTREAM = "sorastream";

  static const List<String> allSources = [
    SOURCE_MOVIEBOX,
    SOURCE_FOURKHDHUB,
    SOURCE_DRAMACHI,
    SOURCE_PUSATFILM,
    SOURCE_JURAGANFILM,
    SOURCE_SAMEHADAKU,
    SOURCE_OTAKUDESU,
    SOURCE_ANICHIN,
    SOURCE_DRACINSI,
    SOURCE_DRAKORKITA,
    SOURCE_SORASTREAM,
  ];

  static final ValueNotifier<String> currentSource =
      ValueNotifier<String>(SOURCE_MOVIEBOX);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keySource) ?? SOURCE_MOVIEBOX;
    currentSource.value = saved;
  }

  static Future<void> setSource(String source) async {
    if (!allSources.contains(source)) {
      return;
    }
    currentSource.value = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySource, source);
  }

  static bool get isMovieBox => currentSource.value == SOURCE_MOVIEBOX;
  static bool get isFourKHdHub => currentSource.value == SOURCE_FOURKHDHUB;
  static bool get isDramachi => currentSource.value == SOURCE_DRAMACHI;
  static bool get isPusatFilm => currentSource.value == SOURCE_PUSATFILM;
  static bool get isJuraganFilm => currentSource.value == SOURCE_JURAGANFILM;
  static bool get isSamehadaku => currentSource.value == SOURCE_SAMEHADAKU;
  static bool get isOtakudesu => currentSource.value == SOURCE_OTAKUDESU;
  static bool get isAnichin => currentSource.value == SOURCE_ANICHIN;
  static bool get isDracinSi => currentSource.value == SOURCE_DRACINSI;
  static bool get isDrakorKita => currentSource.value == SOURCE_DRAKORKITA;
  static bool get isSoraStream => currentSource.value == SOURCE_SORASTREAM;
}
