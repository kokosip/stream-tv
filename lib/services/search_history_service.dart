import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static const String _key = 'search_history_list';
  static const int _maxItems = 20;

  /// Retrieve the list of search queries (newest first)
  static Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Add a query to the search history
  static Future<void> addSearchQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final list = await getSearchHistory();
    // Remove existing occurrence case-insensitively or exact match
    list.removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase());
    // Insert at the front (most recent)
    list.insert(0, trimmed);

    if (list.length > _maxItems) {
      list.removeRange(_maxItems, list.length);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Remove a specific query from search history
  static Future<void> removeSearchQuery(String query) async {
    final list = await getSearchHistory();
    list.removeWhere((item) => item.toLowerCase() == query.trim().toLowerCase());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Clear all search history
  static Future<void> clearAllSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
