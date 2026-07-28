import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _key = 'favorites_list';

  // Get list of favorites
  static Future<List<Map<String, dynamic>>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return [];
    }
  }

  // Check if an item is favorite
  static Future<bool> isFavorite(String subjectId) async {
    final list = await getFavorites();
    return list.any((item) => item['subjectId'] == subjectId);
  }

  // Add to favorites
  static Future<void> addFavorite(Map<String, dynamic> item) async {
    final list = await getFavorites();
    final String subjectId = item['subjectId']?.toString() ?? item['id']?.toString() ?? "";
    if (subjectId.isEmpty) return;
    
    list.removeWhere((x) => x['subjectId'] == subjectId);
    
    // Store fields needed for the list item view
    final newFav = {
      'subjectId': subjectId,
      'title': item['title'] ?? item['subjectTitle'] ?? "Untitled",
      'coverUrl': item['cover']?['url'] ?? item['coverUrl'] ?? "",
      'subjectType': item['subjectType'] ?? item['subject_type'] ?? 1,
      'releaseDate': item['releaseDate'] ?? item['release_date'] ?? "",
    };
    
    list.insert(0, newFav); // Add to the top
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  // Remove from favorites
  static Future<void> removeFavorite(String subjectId) async {
    final list = await getFavorites();
    list.removeWhere((item) => item['subjectId'] == subjectId);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }
}
