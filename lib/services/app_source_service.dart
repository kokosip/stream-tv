import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSourceService {
  static const String _keySource = "app_active_source";

  static const String SOURCE_MOVIEBOX = "moviebox";
  static const String SOURCE_FOURKHDHUB = "4khdhub";
  static const String SOURCE_DRAMACHI = "dramachi";

  static final ValueNotifier<String> currentSource =
      ValueNotifier<String>(SOURCE_MOVIEBOX);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keySource) ?? SOURCE_MOVIEBOX;
    currentSource.value = saved;
  }

  static Future<void> setSource(String source) async {
    if (source != SOURCE_MOVIEBOX && source != SOURCE_FOURKHDHUB && source != SOURCE_DRAMACHI) return;
    currentSource.value = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySource, source);
  }

  static bool get isMovieBox => currentSource.value == SOURCE_MOVIEBOX;
  static bool get isFourKHdHub => currentSource.value == SOURCE_FOURKHDHUB;
  static bool get isDramachi => currentSource.value == SOURCE_DRAMACHI;
}
