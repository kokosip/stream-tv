import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppContentFilterService {
  static const String _keyFilterHindi = "filter_hindi_content";

  /// When true, titles with [Hindi] tags or Hindi dub markers are filtered out.
  /// Defaults to true so original titles are prioritized.
  static final ValueNotifier<bool> filterHindi = ValueNotifier<bool>(true);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // Default is true (filter is ON by default)
    filterHindi.value = prefs.getBool(_keyFilterHindi) ?? true;
  }

  static Future<void> setFilterHindi(bool enabled) async {
    filterHindi.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFilterHindi, enabled);
  }

  /// Pattern matcher for Hindi dub indicators:
  /// Examples: [Hindi], (Hindi), [Hindi Dubbed], (Hindi Dubbed), [Hindi - Org], [Hindi Org], etc.
  static final RegExp _hindiTagRegex = RegExp(
    r'(\[|\()\s*hindi[^\)\]]*(\]|\))',
    caseSensitive: false,
  );

  /// Checks whether a given title string contains a [Hindi] tag or similar dub marker.
  static bool hasHindiTag(String? title) {
    if (title == null || title.trim().isEmpty) return false;
    final clean = title.trim();
    return _hindiTagRegex.hasMatch(clean) ||
        clean.toLowerCase().contains('[hindi]') ||
        clean.toLowerCase().contains('(hindi)');
  }

  /// Checks whether a content item map represents a Hindi-tagged dub.
  static bool isItemHindiDub(dynamic item) {
    if (item is! Map) return false;

    final title = (item['title'] ??
            item['name'] ??
            item['subjectTitle'] ??
            item['subject']?['title'] ??
            item['content'] ??
            '')
        .toString();

    if (hasHindiTag(title)) return true;

    final origTitle = (item['original_title'] ??
            item['original_name'] ??
            item['subject']?['original_title'] ??
            '')
        .toString();

    if (hasHindiTag(origTitle)) return true;

    return false;
  }

  /// Filters a list of items, hiding any Hindi-tagged dubs if the filter is active.
  static List<T> filterList<T>(List<T> items) {
    if (!filterHindi.value) return items;
    return items.where((item) => !isItemHindiDub(item)).toList();
  }
}
