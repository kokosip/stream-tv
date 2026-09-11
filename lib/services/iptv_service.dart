import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class IptvChannel {
  final String id;
  final String name;
  final String? logo;
  final String url;
  final String groupTitle;
  final List<String> categories;
  bool isFavorite;
  final Map<String, String>? httpHeaders;

  IptvChannel({
    required this.id,
    required this.name,
    this.logo,
    required this.url,
    required this.groupTitle,
    List<String>? categories,
    this.isFavorite = false,
    this.httpHeaders,
  }) : categories = categories ?? [groupTitle];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'logo': logo,
    'url': url,
    'groupTitle': groupTitle,
    'categories': categories,
    'isFavorite': isFavorite,
    'httpHeaders': httpHeaders,
  };

  factory IptvChannel.fromJson(Map<String, dynamic> json) {
    final grp = json['groupTitle'] ?? 'Umum';
    List<String> cats = [];
    if (json['categories'] is List) {
      cats = (json['categories'] as List).map((e) => e.toString()).toList();
    }
    if (cats.isEmpty) {
      cats = [grp];
    }
    return IptvChannel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Channel',
      logo: json['logo'],
      url: json['url'] ?? '',
      groupTitle: grp,
      categories: cats,
      isFavorite: json['isFavorite'] == true,
      httpHeaders: json['httpHeaders'] != null 
          ? Map<String, String>.from(json['httpHeaders']) 
          : null,
    );
  }
}

class IptvPlaylist {
  final String id;
  final String name;
  final String? url;
  final bool isDefault;
  final int channelCount;

  IptvPlaylist({
    required this.id,
    required this.name,
    this.url,
    this.isDefault = false,
    this.channelCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'isDefault': isDefault,
    'channelCount': channelCount,
  };

  factory IptvPlaylist.fromJson(Map<String, dynamic> json) => IptvPlaylist(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    url: json['url'],
    isDefault: json['isDefault'] == true,
    channelCount: json['channelCount'] ?? 0,
  );
}

class IptvService {
  IptvService._internal();
  static final IptvService instance = IptvService._internal();

  static const String _prefPlaylistsKey = 'iptv_playlists';
  static const String _prefActivePlaylistIdKey = 'iptv_active_playlist_id';
  static const String _prefFavoritesKey = 'iptv_favorites';
  static const String _defaultIndonesiaUrl = 'https://iptv-org.github.io/iptv/countries/id.m3u';

  List<IptvPlaylist> _playlists = [];
  String _activePlaylistId = 'default_id';
  List<IptvChannel> _currentChannels = [];
  Set<String> _favoriteUrls = {};

  List<IptvPlaylist> get playlists => _playlists;
  String get activePlaylistId => _activePlaylistId;
  List<IptvChannel> get currentChannels => _currentChannels;

  /// Built-in fallback channels for Indonesia in case offline or upstream network issues
  static final List<IptvChannel> _builtInIndonesiaChannels = [
    IptvChannel(
      id: 'tvri_nasional',
      name: 'TVRI Nasional',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/TVRI_Nasional_2019.svg/512px-TVRI_Nasional_2019.svg.png',
      url: 'https://ott-linear.metrotvnews.com/live-eds/tvri/index.m3u8',
      groupTitle: 'Nasional',
    ),
    IptvChannel(
      id: 'kompas_tv',
      name: 'Kompas TV',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Kompas_TV_2017.svg/512px-Kompas_TV_2017.svg.png',
      url: 'https://stream.kompas.tv/live/kompastv/playlist.m3u8',
      groupTitle: 'Berita',
    ),
    IptvChannel(
      id: 'metro_tv',
      name: 'Metro TV HD',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/67/MetroTV_2010.svg/512px-MetroTV_2010.svg.png',
      url: 'https://ott-linear.metrotvnews.com/live-eds/metrotv/index.m3u8',
      groupTitle: 'Berita',
    ),
    IptvChannel(
      id: 'cnn_indonesia',
      name: 'CNN Indonesia',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/CNN_Indonesia.svg/512px-CNN_Indonesia.svg.png',
      url: 'https://live.cnbcindonesia.com/live/cnn/smil:cnn.smil/playlist.m3u8',
      groupTitle: 'Berita',
    ),
    IptvChannel(
      id: 'cnbc_indonesia',
      name: 'CNBC Indonesia',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/CNBC_Indonesia.svg/512px-CNBC_Indonesia.svg.png',
      url: 'https://live.cnbcindonesia.com/live/cnbc/smil:cnbc.smil/playlist.m3u8',
      groupTitle: 'Bisnis & Berita',
    ),
    IptvChannel(
      id: 'beritasatu',
      name: 'BTV (BeritaSatu)',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/30/BTV_logo.svg/512px-BTV_logo.svg.png',
      url: 'https://stream.beritasatu.tv/live/beritasatu/playlist.m3u8',
      groupTitle: 'Berita',
    ),
    IptvChannel(
      id: 'tvri_sport',
      name: 'TVRI Sport HD',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f6/TVRI_Sport_HD_2019.svg/512px-TVRI_Sport_HD_2019.svg.png',
      url: 'https://ott-linear.metrotvnews.com/live-eds/tvrisport/index.m3u8',
      groupTitle: 'Olahraga',
    ),
    IptvChannel(
      id: 'rri_net',
      name: 'RRI Net',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/RRI_Net_2023.svg/512px-RRI_Net_2023.svg.png',
      url: 'https://rrinet.rri.co.id/live/rrinet/playlist.m3u8',
      groupTitle: 'Musik & Informasi',
    ),
    IptvChannel(
      id: 'rodja_tv',
      name: 'Rodja TV',
      logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/Rodja_TV.png/512px-Rodja_TV.png',
      url: 'https://live.rodja.tv/live/rodjatv.m3u8',
      groupTitle: 'Religi',
    ),
  ];

  /// Initialize service and load stored preferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load favorites
    final favList = prefs.getStringList(_prefFavoritesKey) ?? [];
    _favoriteUrls = favList.toSet();

    // Load playlists list
    final rawPlaylists = prefs.getString(_prefPlaylistsKey);
    if (rawPlaylists != null && rawPlaylists.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(rawPlaylists);
        _playlists = decoded.map((e) => IptvPlaylist.fromJson(e)).toList();
      } catch (_) {
        _playlists = [];
      }
    }

    // Ensure default Indonesia playlist exists
    final hasDefault = _playlists.any((p) => p.isDefault || p.id == 'default_id');
    if (!hasDefault) {
      final defaultPlaylist = IptvPlaylist(
        id: 'default_id',
        name: 'IPTV Indonesia (Default)',
        url: _defaultIndonesiaUrl,
        isDefault: true,
        channelCount: _builtInIndonesiaChannels.length,
      );
      _playlists.insert(0, defaultPlaylist);
      await _savePlaylists();
    }

    // Load active playlist ID
    _activePlaylistId = prefs.getString(_prefActivePlaylistIdKey) ?? 'default_id';
    if (!_playlists.any((p) => p.id == _activePlaylistId)) {
      _activePlaylistId = _playlists.first.id;
    }
  }

  /// Saves playlists metadata to SharedPreferences
  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_playlists.map((p) => p.toJson()).toList());
    await prefs.setString(_prefPlaylistsKey, raw);
  }

  /// Sets the active playlist and refreshes channels
  Future<List<IptvChannel>> switchPlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => _playlists.first,
    );
    _activePlaylistId = playlist.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActivePlaylistIdKey, _activePlaylistId);
    return loadChannels(forceRefresh: false);
  }

  /// Adds a custom user M3U playlist
  Future<IptvPlaylist> addPlaylist({required String name, required String url}) async {
    final newId = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    final playlist = IptvPlaylist(
      id: newId,
      name: name.trim().isEmpty ? 'My Playlist' : name.trim(),
      url: url.trim(),
      isDefault: false,
    );
    _playlists.add(playlist);
    await _savePlaylists();
    await switchPlaylist(newId);
    return playlist;
  }

  /// Deletes a custom playlist (cannot delete default)
  Future<void> deletePlaylist(String playlistId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1 && !_playlists[index].isDefault) {
      _playlists.removeAt(index);
      await _savePlaylists();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('iptv_cache_$playlistId');

      if (_activePlaylistId == playlistId) {
        await switchPlaylist('default_id');
      }
    }
  }

  /// Toggle channel favorite state
  Future<void> toggleFavorite(IptvChannel channel) async {
    if (_favoriteUrls.contains(channel.url)) {
      _favoriteUrls.remove(channel.url);
      channel.isFavorite = false;
    } else {
      _favoriteUrls.add(channel.url);
      channel.isFavorite = true;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefFavoritesKey, _favoriteUrls.toList());
  }

  bool isFavorite(String url) => _favoriteUrls.contains(url);

  /// Loads channels for the currently active playlist
  Future<List<IptvChannel>> loadChannels({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'iptv_cache_$_activePlaylistId';

    if (!forceRefresh) {
      final cachedRaw = prefs.getString(cacheKey);
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(cachedRaw);
          final list = decoded.map((e) => IptvChannel.fromJson(e)).toList();
          if (list.isNotEmpty) {
            for (final ch in list) {
              ch.isFavorite = _favoriteUrls.contains(ch.url);
            }
            _currentChannels = list;
            return list;
          }
        } catch (_) {}
      }
    }

    final playlist = _playlists.firstWhere(
      (p) => p.id == _activePlaylistId,
      orElse: () => _playlists.first,
    );

    List<IptvChannel> fetchedChannels = [];

    // If online URL provided, attempt fetch
    if (playlist.url != null && playlist.url!.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(playlist.url!), headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 StreamTV/1.0',
          'Accept': '*/*',
        }).timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          fetchedChannels = parseM3u(res.body);
        }
      } catch (_) {
        // Fallback to offline built-ins if network fails on default playlist
      }
    }

    // If still empty and it's default Indonesia playlist, use offline built-in
    if (fetchedChannels.isEmpty && playlist.isDefault) {
      fetchedChannels = List.from(_builtInIndonesiaChannels);
    }

    // Mark favorite status
    for (final ch in fetchedChannels) {
      ch.isFavorite = _favoriteUrls.contains(ch.url);
    }

    _currentChannels = fetchedChannels;

    // Cache to SharedPreferences
    if (fetchedChannels.isNotEmpty) {
      final jsonStr = jsonEncode(fetchedChannels.map((c) => c.toJson()).toList());
      await prefs.setString(cacheKey, jsonStr);

      // Update channel count in playlist metadata
      final plIndex = _playlists.indexWhere((p) => p.id == playlist.id);
      if (plIndex != -1) {
        _playlists[plIndex] = IptvPlaylist(
          id: playlist.id,
          name: playlist.name,
          url: playlist.url,
          isDefault: playlist.isDefault,
          channelCount: fetchedChannels.length,
        );
        await _savePlaylists();
      }
    }

    return _currentChannels;
  }

  /// Parses M3U / M3U_PLUS content string into a list of [IptvChannel]
  List<IptvChannel> parseM3u(String content) {
    final List<IptvChannel> channels = [];
    final lines = LineSplitter.split(content).map((l) => l.trim()).toList();

    String currentName = '';
    String? currentLogo;
    String currentGroup = 'Umum';
    String currentId = '';
    Map<String, String>? currentHeaders;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // Extract channel name after comma
        final commaIndex = line.indexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = 'Channel ${channels.length + 1}';
        }

        // Extract tvg-logo
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false).firstMatch(line);
        currentLogo = logoMatch?.group(1);

        // Extract group-title
        final groupMatch = RegExp(r'group-title="([^"]*)"', caseSensitive: false).firstMatch(line);
        currentGroup = groupMatch?.group(1) ?? 'Umum';
        if (currentGroup.trim().isEmpty) currentGroup = 'Umum';

        // Extract tvg-id or tvg-name
        final idMatch = RegExp(r'tvg-id="([^"]*)"', caseSensitive: false).firstMatch(line);
        currentId = idMatch?.group(1) ?? '';
        if (currentId.isEmpty) {
          currentId = 'ch_${channels.length + 1}';
        }
      } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
        final ua = line.substring('#EXTVLCOPT:http-user-agent='.length).trim();
        if (ua.isNotEmpty) {
          currentHeaders ??= {};
          currentHeaders['User-Agent'] = ua;
        }
      } else if (!line.startsWith('#')) {
        // URL line
        final streamUrl = line;
        if (streamUrl.startsWith('http://') || streamUrl.startsWith('https://') || streamUrl.startsWith('rtmp://')) {
          final catList = _extractCleanCategories(currentGroup);
          final primaryCat = catList.first;

          channels.add(IptvChannel(
            id: currentId.isNotEmpty ? currentId : 'ch_${channels.length + 1}',
            name: currentName.isNotEmpty ? currentName : 'Channel ${channels.length + 1}',
            logo: currentLogo,
            url: streamUrl,
            groupTitle: primaryCat,
            categories: catList,
            httpHeaders: currentHeaders,
          ));
        }

        // Reset for next entry
        currentName = '';
        currentLogo = null;
        currentGroup = 'Umum';
        currentId = '';
        currentHeaders = null;
      }
    }

    return channels;
  }

  /// Splits multi-genre categories separated by ';' or ',' and normalizes them cleanly
  List<String> _extractCleanCategories(String rawGroup) {
    if (rawGroup.trim().isEmpty) return ['Umum'];

    final parts = rawGroup.split(RegExp(r'[;,]')).map((p) => p.trim()).where((p) => p.isNotEmpty);
    final Set<String> cleanSet = {};

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.contains('news') || lower.contains('berita')) {
        cleanSet.add('Berita');
      } else if (lower.contains('sport') || lower.contains('olahraga')) {
        cleanSet.add('Olahraga');
      } else if (lower.contains('movie') || lower.contains('cinema') || lower.contains('film') || lower.contains('series')) {
        cleanSet.add('Film & Serial');
      } else if (lower.contains('music') || lower.contains('musik')) {
        cleanSet.add('Musik');
      } else if (lower.contains('kid') || lower.contains('anak') || lower.contains('kartun') || lower.contains('animat')) {
        cleanSet.add('Anak-anak');
      } else if (lower.contains('religi') || lower.contains('islam') || lower.contains('dakwah') || lower.contains('christian') || lower.contains('spiritual')) {
        cleanSet.add('Religi');
      } else if (lower.contains('culture') || lower.contains('budaya') || lower.contains('lifestyle') || lower.contains('travel')) {
        cleanSet.add('Budaya & Gaya Hidup');
      } else if (lower.contains('education') || lower.contains('pendidikan') || lower.contains('docu') || lower.contains('science')) {
        cleanSet.add('Edukasi');
      } else if (lower.contains('entertain') || lower.contains('hiburan') || lower.contains('comedy')) {
        cleanSet.add('Hiburan');
      } else if (lower.contains('nasional') || lower.contains('general') || lower.contains('indo') || lower.contains('public') || lower.contains('legislat')) {
        cleanSet.add('Nasional');
      } else if (lower.contains('business') || lower.contains('bisnis') || lower.contains('finance') || lower.contains('ekonomi')) {
        cleanSet.add('Bisnis & Berita');
      } else {
        final formatted = part[0].toUpperCase() + part.substring(1).toLowerCase();
        cleanSet.add(formatted);
      }
    }

    if (cleanSet.isEmpty) return ['Umum'];
    return cleanSet.toList();
  }
}
