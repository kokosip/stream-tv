import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/iptv_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'live_tv_player_screen.dart';

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  final IptvService _iptv = IptvService.instance;

  bool _isLoading = true;
  String _selectedCategory = "Semua";
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  List<IptvChannel> _allChannels = [];
  List<String> _categories = ["Semua", "⭐ Favorit"];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    await _iptv.init();
    final channels = await _iptv.loadChannels(forceRefresh: forceRefresh);

    // Extract dynamic clean categories from all channel multi-categories
    final Set<String> groupSet = {};
    for (final ch in channels) {
      for (final cat in ch.categories) {
        if (cat.trim().isNotEmpty && !cat.contains(';')) {
          groupSet.add(cat.trim());
        }
      }
    }

    final catList = ["Semua", "⭐ Favorit", ...groupSet.toList()..sort()];

    if (mounted) {
      setState(() {
        _allChannels = channels;
        _categories = catList;
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = "Semua";
        }
        _isLoading = false;
      });
    }
  }

  List<IptvChannel> get _filteredChannels {
    List<IptvChannel> list = _allChannels;

    if (_selectedCategory == "⭐ Favorit") {
      list = list.where((c) => c.isFavorite).toList();
    } else if (_selectedCategory != "Semua") {
      list = list.where((c) => c.categories.contains(_selectedCategory) || c.groupTitle == _selectedCategory).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) || 
               c.groupTitle.toLowerCase().contains(q) ||
               c.categories.any((cat) => cat.toLowerCase().contains(q));
      }).toList();
    }

    return list;
  }

  void _openAddPlaylistDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.playlist_add_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            Text(
              "Tambah Playlist M3U",
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Nama Playlist (Contoh: My TV)",
                  labelStyle: GoogleFonts.outfit(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "URL Playlist M3U / M3U8 (http/https)",
                  labelStyle: GoogleFonts.outfit(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Batal", style: GoogleFonts.outfit(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Harap masukkan URL M3U yang valid (dimulai http/https)")),
                );
                return;
              }
              Navigator.pop(context);
              await _iptv.addPlaylist(
                name: nameController.text.trim(),
                url: url,
              );
              _initAndLoad(forceRefresh: true);
            },
            child: Text("Simpan & Muat", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openPlaylistSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final playlists = _iptv.playlists;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Pilih Playlist IPTV",
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              ...playlists.map((pl) {
                final isSelected = pl.id == _iptv.activePlaylistId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: TvFocusableCard(
                    onTap: () async {
                      Navigator.pop(context);
                      await _iptv.switchPlaylist(pl.id);
                      _initAndLoad();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2E1518) : const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSelected ? Colors.redAccent : Colors.transparent, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(pl.isDefault ? Icons.flag_rounded : Icons.playlist_play_rounded, 
                              color: isSelected ? Colors.redAccent : Colors.white70),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pl.name,
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  "${pl.channelCount} Saluran TV • ${pl.isDefault ? 'Preset Resmi' : 'Custom User'}",
                                  style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (!pl.isDefault)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () async {
                                Navigator.pop(context);
                                await _iptv.deletePlaylist(pl.id);
                                _initAndLoad();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800 && size.height > 500;
    final isWideScreen = size.width >= 720 && size.height > 500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header Toolbar with Integrated Search and Action Buttons
        _buildHeaderToolbar(isTv, isWideScreen),
        const SizedBox(height: 10),

        // 2. Main Content
        Expanded(
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SpinKitRing(color: Colors.redAccent, size: 44.0),
                      SizedBox(height: 16),
                      Text("Memuat saluran TV...", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              : _allChannels.isEmpty
                  ? _buildEmptyState()
                  : isWideScreen
                      // Wide / TV Layout: Sidebar Categories on Left + Channels on Right
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 170,
                              child: _buildCategoriesSidebar(isTv),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildChannelsGrid(isTv, isWideScreen),
                            ),
                          ],
                        )
                      // Mobile / Portrait Layout: Horizontal Category Chips + Full Width Channels Grid
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 38,
                              child: _buildCategoriesHorizontal(),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _buildChannelsGrid(isTv, isWideScreen),
                            ),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildHeaderToolbar(bool isTv, bool isWideScreen) {
    final activePl = _iptv.playlists.firstWhere(
      (p) => p.id == _iptv.activePlaylistId,
      orElse: () => _iptv.playlists.isNotEmpty ? _iptv.playlists.first : IptvPlaylist(id: '', name: 'IPTV Indonesia'),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF262626), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Title + Scrollable Action Buttons (Never Overflows)
          Row(
            children: [
              const Icon(Icons.live_tv_rounded, color: Colors.redAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Live TV",
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "${activePl.name} (${_filteredChannels.length} TV)",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Scrollable action buttons
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TvFocusableCard(
                      onTap: _openPlaylistSelector,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text("Playlist", style: GoogleFonts.outfit(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    TvFocusableCard(
                      onTap: _openAddPlaylistDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent, width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.add_link_rounded, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 4),
                            Text("+ M3U", style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    TvFocusableCard(
                      onTap: () => _initAndLoad(forceRefresh: true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Search Bar Input (Centered, Symmetrical & Sleek)
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E2E2E), width: 1),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              textAlignVertical: TextAlignVertical.center,
              cursorColor: Colors.redAccent,
              cursorHeight: 16,
              cursorWidth: 2,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: "Cari stasiun TV (misal: Kompas, TVRI, CNN, Sport)...",
                hintStyle: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 12),
                prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60, size: 18),
                suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSidebar(bool isTv) {
    return ListView.builder(
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        final isSelected = cat == _selectedCategory;

        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: TvFocusableCard(
            onTap: () => setState(() => _selectedCategory = cat),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? Colors.redAccent : const Color(0xFF181818),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                cat,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoriesHorizontal() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        final isSelected = cat == _selectedCategory;

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: TvFocusableCard(
            onTap: () => setState(() => _selectedCategory = cat),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.redAccent : const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? Colors.redAccent : const Color(0xFF2C2C2C), width: 1),
              ),
              child: Text(
                cat,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : Colors.grey.shade300,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelsGrid(bool isTv, bool isWideScreen) {
    final channels = _filteredChannels;

    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 44),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty
                  ? "Tidak ada saluran cocok dengan '$_searchQuery'"
                  : "Tidak ada saluran di kategori $_selectedCategory",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTv ? 4 : (isWideScreen ? 3 : 2),
        childAspectRatio: isTv ? 1.45 : 1.35,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final ch = channels[index];

        return TvFocusableCard(
          onTap: () {
            final trueIndex = _allChannels.indexOf(ch);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LiveTvPlayerScreen(
                  channels: _allChannels,
                  initialIndex: trueIndex != -1 ? trueIndex : index,
                ),
              ),
            ).then((_) {
              setState(() {});
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF282828), width: 1),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top: Category Badge & Favorite Star
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ch.groupTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (ch.isFavorite)
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                  ],
                ),

                // Center: Channel Logo
                Expanded(
                  child: Center(
                    child: ch.logo != null && ch.logo!.isNotEmpty
                        ? Image.network(
                            ch.logo!,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const Icon(Icons.live_tv_rounded, color: Colors.white24, size: 28),
                          )
                        : const Icon(Icons.live_tv_rounded, color: Colors.redAccent, size: 28),
                  ),
                ),

                // Bottom: Channel Name & Live Indicator Dot
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.playlist_remove_rounded, color: Colors.redAccent, size: 52),
          const SizedBox(height: 14),
          Text(
            "Tidak Ada Saluran TV Ditemukan",
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "Coba segarkan atau tambahkan URL playlist M3U Anda.",
            style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => _initAndLoad(forceRefresh: true),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
            label: Text("Segarkan Saluran", style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
