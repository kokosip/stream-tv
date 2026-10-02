import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _key = 'favorites_list';

  // In-memory cache for O(1) lookups
  static List<Map<String, dynamic>>? _cachedList;
  static Set<String>? _cachedIds;

  static void _invalidateCache() {
    _cachedList = null;
    _cachedIds = null;
  }

  static Future<void> _ensureCache() async {
    if (_cachedList != null && _cachedIds != null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_key);
    if (jsonStr == null) {
      _cachedList = [];
      _cachedIds = {};
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _cachedList = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
      _cachedIds = _cachedList!.map((item) => item['subjectId']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (_) {
      _cachedList = [];
      _cachedIds = {};
    }
  }

  // Get list of favorites
  static Future<List<Map<String, dynamic>>> getFavorites() async {
    await _ensureCache();
    return List.unmodifiable(_cachedList!);
  }

  // Check if an item is favorite - O(1) via HashSet
  static Future<bool> isFavorite(String subjectId) async {
    await _ensureCache();
    return _cachedIds!.contains(subjectId);
  }

  // Add to favorites
  static Future<void> addFavorite(Map<String, dynamic> item) async {
    await _ensureCache();
    final String subjectId = item['subjectId']?.toString() ?? item['id']?.toString() ?? "";
    if (subjectId.isEmpty) return;
    
    _cachedList!.removeWhere((x) => x['subjectId'] == subjectId);
    
    // Store fields needed for the list item view
    final newFav = {
      'subjectId': subjectId,
      'title': item['title'] ?? item['subjectTitle'] ?? "Untitled",
      'coverUrl': item['cover']?['url'] ?? item['coverUrl'] ?? "",
      'subjectType': item['subjectType'] ?? item['subject_type'] ?? 1,
      'releaseDate': item['releaseDate'] ?? item['release_date'] ?? item['year']?.toString() ?? "",
      'provider': item['provider'] ??
          (subjectId.startsWith('dramachi_') || subjectId.contains('::')
              ? 'dramachi'
              : (subjectId.startsWith('/') ? '4khdhub' : 'moviebox')),
    };
    
    _cachedList!.insert(0, newFav); // Add to the top
    _cachedIds!.add(subjectId);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_cachedList));
  }

  // Remove from favorites
  static Future<void> removeFavorite(String subjectId) async {
    await _ensureCache();
    _cachedList!.removeWhere((item) => item['subjectId'] == subjectId);
    _cachedIds!.remove(subjectId);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_cachedList));
  }
}
