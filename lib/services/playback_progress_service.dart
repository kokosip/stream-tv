import 'package:shared_preferences/shared_preferences.dart';

class PlaybackProgressService {
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

  // Save progress in milliseconds
  static Future<void> saveProgress(String subjectId, int season, int episode, int positionMs, int durationMs) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    
    // If the progress is near the end (more than 95%), clear it so it starts from the beginning next time
    if (durationMs > 0 && positionMs > durationMs * 0.95) {
      await prefs.remove(key);
      return;
    }

    // Don't save if progress is negligible (less than 5 seconds)
    if (positionMs < 5000) {
      await prefs.remove(key);
      return;
    }

    await prefs.setInt(key, positionMs);
  }

  // Clear progress
  static Future<void> clearProgress(String subjectId, int season, int episode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    await prefs.remove(key);
  }
}
