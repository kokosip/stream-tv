import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackProgressService {
  static const String _recentPlaysKey = 'recent_plays_list';

  static String _getKey(String subjectId, int season, int episode) {
    if (season > 0 || episode > 0) {
      return 'playback_progress_${subjectId}_s${season}_e$episode';
    }
    return 'playback_progress_$subjectId';
  }

  // Get progress in milliseconds
  static Future<int> getProgress(String subjectId, int season, int episode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    return prefs.getInt(key) ?? 0;
  }

  // Get list of recent plays
  static Future<List<Map<String, dynamic>>> getRecentPlays() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_recentPlaysKey);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return [];
    }
  }

  // Get recent play entry for a specific subjectId
  static Future<Map<String, dynamic>?> getRecentPlay(String subjectId) async {
    final list = await getRecentPlays();
    try {
      return list.firstWhere((item) => item['subjectId']?.toString() == subjectId);
    } catch (_) {
      return null;
    }
  }

  // Save progress in milliseconds, with optional metadata for "Lanjutkan Nonton"
  static Future<void> saveProgress(
    String subjectId,
    int season,
    int episode,
    int positionMs,
    int durationMs, {
    String? title,
    String? coverUrl,
    int? subjectType,
    int? maxEpisodesInSeason,
    String? provider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    
    // An episode is finished if >= 90% watched or within last 30s
    bool isFinished = durationMs > 0 && (positionMs >= durationMs * 0.90 || (durationMs - positionMs) <= 30000);
    bool isNegligible = positionMs < 5000;

    // If progress is completed or negligible, clear the direct position key
    if (isFinished || isNegligible) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, positionMs);
    }

    // Update the recent plays list if metadata is supplied
    if (title != null && title.isNotEmpty) {
      if (isNegligible && !isFinished) {
        // Do not add to recent list if it was barely started
        return;
      }

      final recentList = await getRecentPlays();
      recentList.removeWhere((item) => item['subjectId'] == subjectId);

      // Smart Episode Advancement:
      // If a series episode finishes, automatically cue the next episode in Continue Watching!
      int savedSeason = season;
      int savedEpisode = episode;
      int savedPos = isFinished ? 0 : positionMs;
      bool isNextCue = false;

      if (isFinished && (season > 0 || episode > 0)) {
        if (maxEpisodesInSeason != null && episode >= maxEpisodesInSeason) {
          savedSeason = season + 1;
          savedEpisode = 1;
        } else {
          savedEpisode = episode + 1;
        }
        isNextCue = true;
      }

      final entry = {
        'subjectId': subjectId,
        'provider': provider ?? (subjectId.startsWith('/') || subjectId.contains('-movie-') || subjectId.contains('-series-') ? '4khdhub' : 'moviebox'),
        'season': savedSeason,
        'episode': savedEpisode,
        'originalSeason': season,
        'originalEpisode': episode,
        'title': title,
        'coverUrl': coverUrl ?? '',
        'subjectType': subjectType ?? 1,
        'positionMs': savedPos,
        'durationMs': durationMs,
        'isNextCue': isNextCue,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      recentList.insert(0, entry);
      if (recentList.length > 15) {
        recentList.removeRange(15, recentList.length);
      }

      await prefs.setString(_recentPlaysKey, jsonEncode(recentList));
    }
  }

  // Clear progress
  static Future<void> clearProgress(String subjectId, int season, int episode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    await prefs.remove(key);
    
    // Also remove from recent plays list
    try {
      final recentList = await getRecentPlays();
      recentList.removeWhere((item) => item['subjectId'] == subjectId);
      await prefs.setString(_recentPlaysKey, jsonEncode(recentList));
    } catch (_) {}
  }
}

