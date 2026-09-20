import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EpisodeProgress {
  final int positionMs;
  final int durationMs;
  final bool isFinished;

  const EpisodeProgress({
    this.positionMs = 0,
    this.durationMs = 0,
    this.isFinished = false,
  });

  double get ratio {
    if (isFinished) return 1.0;
    if (durationMs <= 0 || positionMs <= 0) return 0.0;
    final r = positionMs / durationMs;
    return r.clamp(0.04, 0.96);
  }

  bool get hasProgress => isFinished || positionMs > 0;

  String get positionFormatted {
    final minutes = positionMs ~/ 60000;
    if (minutes < 1) return "< 1m";
    return "${minutes}m";
  }
}

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

  // Get detailed progress (position, duration, completion) for an episode
  static Future<EpisodeProgress> getEpisodeProgress(
    String subjectId,
    int season,
    int episode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    final pos = prefs.getInt(key) ?? 0;
    final dur = prefs.getInt('${key}_dur') ?? 0;
    final fin = prefs.getBool('${key}_fin') ?? false;
    return EpisodeProgress(
      positionMs: pos,
      durationMs: dur,
      isFinished: fin,
    );
  }

  // Get progress for multiple episodes in batch for fast UI rendering
  static Future<Map<int, EpisodeProgress>> getSeasonProgress(
    String subjectId,
    int season,
    List<int> episodeNumbers,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<int, EpisodeProgress> result = {};

    // Discover all episode numbers from stored keys for this subject and season
    final prefix = 'playback_progress_${subjectId}_s${season}_e';
    final Set<int> allEps = Set<int>.from(episodeNumbers);
    for (final k in prefs.getKeys()) {
      if (k.startsWith(prefix)) {
        final rest = k.substring(prefix.length);
        final epStr = rest.split('_').first;
        final ep = int.tryParse(epStr);
        if (ep != null) {
          allEps.add(ep);
        }
      }
    }

    // Check recent plays for fallback duration/position if newly added
    Map<String, dynamic>? matchingRecent;
    try {
      final recents = await getRecentPlays();
      for (final r in recents) {
        if (r['subjectId']?.toString() == subjectId &&
            ((r['originalSeason'] ?? r['season']) == season)) {
          matchingRecent = r;
          final rEp = (matchingRecent['originalEpisode'] ?? matchingRecent['episode']) as int?;
          if (rEp != null && rEp > 0) allEps.add(rEp);
          break;
        }
      }
    } catch (_) {}

    for (final ep in allEps) {
      final key = _getKey(subjectId, season, ep);
      int pos = prefs.getInt(key) ?? 0;
      int dur = prefs.getInt('${key}_dur') ?? 0;
      bool fin = prefs.getBool('${key}_fin') ?? false;

      if (matchingRecent != null && (dur <= 0 || (pos <= 0 && !fin))) {
        final rEp = matchingRecent['originalEpisode'] ?? matchingRecent['episode'];
        if (rEp == ep) {
          if (dur <= 0) {
            dur = (matchingRecent['durationMs'] as num?)?.toInt() ?? 0;
          }
          if (pos <= 0 && !fin) {
            pos = (matchingRecent['positionMs'] as num?)?.toInt() ?? 0;
          }
        }
      }

      if (fin || pos > 0) {
        result[ep] = EpisodeProgress(
          positionMs: pos,
          durationMs: dur > 0 ? dur : 2700000,
          isFinished: fin,
        );
      }
    }
    return result;
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
    final durKey = '${key}_dur';
    final finKey = '${key}_fin';
    
    // An episode is finished if >= 90% watched or within last 30s
    bool isFinished = durationMs > 0 && (positionMs >= durationMs * 0.90 || (durationMs - positionMs) <= 30000);
    bool isNegligible = positionMs < 5000;

    if (durationMs > 0) {
      await prefs.setInt(durKey, durationMs);
    }

    // If progress is completed or negligible, handle position & finished keys
    if (isFinished) {
      await prefs.remove(key); // Resume from beginning next time
      await prefs.setBool(finKey, true);
    } else if (isNegligible) {
      await prefs.remove(key);
      await prefs.remove(finKey);
    } else {
      await prefs.setInt(key, positionMs);
      await prefs.setBool(finKey, false);
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

  // Clear progress for a specific episode
  static Future<void> clearProgress(String subjectId, int season, int episode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(subjectId, season, episode);
    await prefs.remove(key);
    await prefs.remove('${key}_dur');
    await prefs.remove('${key}_fin');
    
    // Also remove from recent plays list
    try {
      final recentList = await getRecentPlays();
      recentList.removeWhere((item) => item['subjectId'] == subjectId);
      await prefs.setString(_recentPlaysKey, jsonEncode(recentList));
    } catch (_) {}
  }

  // Remove a specific item from recent plays/history entirely
  static Future<void> removeRecentPlay(String subjectId) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final recentList = await getRecentPlays();
      recentList.removeWhere((item) => item['subjectId']?.toString() == subjectId);
      await prefs.setString(_recentPlaysKey, jsonEncode(recentList));

      // Remove related position progress keys
      final prefix = 'playback_progress_$subjectId';
      final keys = prefs.getKeys().where((k) => k == prefix || k.startsWith('${prefix}_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  // Clear all watch history / recent plays
  static Future<void> clearAllRecentPlays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentPlaysKey);

    // Remove all playback progress keys
    final keys = prefs.getKeys().where((k) => k.startsWith('playback_progress_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}

