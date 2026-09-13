# StreamTV (TMDB, MovieBox & 4KHDHub TV Client)

A premium, cinema-grade Flutter streaming application designed specifically for **Android TV** and **Android** devices. Built for an effortless 10-foot viewing experience with full D-Pad remote control support.

---

## 🌟 Key Features

### 1. 🎬 Multi-Provider Streaming Engine
- **MovieBox API**: Stream thousands of global movies and TV series with multiple audio dubs and subtitle tracks.
- **4KHDHub Integration (4K UHD & 1080p REMUX)**:
  - Access ultra-high-definition releases up to **4K UHD (2160p REMUX, HDR10, Dolby Vision)** and **1080p 10-Bit**.
  - Dynamic HubCloud CDN mirror resolver with smart fallback and preflight byte-range probing to guarantee working stream links.
- **Multi-Provider Search**: Search MovieBox and 4KHDHub simultaneously with provider filter chips and clear visual badges (`[4KHDHub]` and `[MovieBox]`).

### 2. 🍿 Streaming Platforms & OTT Network Catalog (Netflix, Disney+, Prime & More)
- **Official TMDB Watch Providers Integration**: Browse movies and series curated directly from global OTT streaming giants:
  - 🔴 **Netflix**
  - 🔵 **Disney+**
  - 🔷 **Amazon Prime Video**
  - 🍏 **Apple TV+**
  - 🟣 **HBO Max**
  - 🟡 **Viu** (Asian & Korean drama hits)
- **Home Streaming Shortcut Bar**: Beautiful, glowing platform cards positioned on the Home screen for one-touch remote or touch navigation.
- **Dedicated Provider Catalog (`ProviderCatalogScreen`)**:
  - Filter content by **All**, **Movies**, or **TV Series**.
  - Responsive poster grid (2–3 columns on mobile, 5–6 columns on Android TV).
  - Infinite scroll pagination and TV D-Pad focus scaling.
  - Automatic stream bridging to MovieBox and 4KHDHub resolvers.

### 3. 💾 Offline Storage & Download Engine
- **Background Downloader**: Download movies and full TV episodes for offline viewing without requiring an active internet connection.
- **Multi-Resolution Download Selector**: Choose preferred resolutions (360p, 480p, 720p HD, 1080p Full HD) with estimated file size badges.
- **Dedicated Downloads Manager Tab**:
  - Storage space gauge showing downloaded items count and device memory usage.
  - Active download tiles with real-time transfer speed (`MB/s`), progress percentage bar, and pause/resume/cancel controls.
  - Completed offline titles with instant playback and delete confirmations.
- **Integrated Offline Player**: Direct playback from local device storage without network latency.

### 4. ⭐ Real-Time TMDB Catalog & Auto-Bridge Engine
- **The Movie Database (TMDB) Integration**: Features a live, up-to-the-minute global catalog powered by official TMDB API endpoints:
  - **Now Playing in Theaters (`🔥 In Theatres (Now Playing)`)**: Direct access to newly released cinema box-office movies.
  - **Daily Trending Movies (`⭐ Trending Movies Today`)**: Top trending movies worldwide updated in real-time.
  - **Weekly Trending TV Shows (`📺 Popular TV Shows`)**: Worldwide television and streaming series.
  - **Curated Platform Rows**: Dedicated Home screen rows for *🍿 Netflix Top Picks* and *✨ Disney+ Highlights*.
  - **Ultra-HD Hero Spotlight Banner**: High-resolution 1080p wide backdrops, official community ratings, and synopses.
- **Intelligent Auto-Bridge to Playback**:
  - Automatically bridges TMDB metadata with available streaming servers (**4KHDHub** for 4K UHD/1080p REMUX and **MovieBox** for multi-language audio & subtitles).
  - Interactive source selector (`[💎 4KHDHub (4K / 1080p)]` and `[🎬 MovieBox (Multi-Audio)]`) lets viewers choose their preferred release on the fly.
  - Informative cinema alert dialog if a movie is newly released in theaters and hasn't arrived on streaming servers yet.
  - 15-minute in-memory cache TTL for instant remote navigation without API rate-limit bottlenecks.

### 5. 🌐 Real-Time Bilingual Localization (EN / ID)
- **Instant Dual-Language Switching**: Seamlessly toggle between English (`EN`) and Indonesian (`ID`) from the top header or settings tab.
- **Dynamic Real-Time Rebuild**: Uses reactive listeners so all catalog titles, filter dropdowns, navigation badges, and system dialogs update instantaneously without restarting the app.

### 6. 📺 TVMaze API Metadata Catalog
- **Rich TV Series Metadata**: Integrated with the open **[TVMaze API](https://www.tvmaze.com/)** to enrich TV series cataloging.
- **16:9 Episode Still Thumbnails**: Each episode card showcases the official scene still shot instead of a generic show poster.
- **Official Episode Names & Synopses**: Displays genuine episode titles (e.g., *"Glorious Purpose"*, *"Winter is Coming"*) and full plot summaries cleanly stripped of HTML formatting.
- **Gold Star Episode Ratings**: Highlights community ratings directly on the episode cards.
- **In-Memory Caching & Title Normalizer**: Automatically handles show name variations and caches responses to keep navigation blazing fast.

### 7. 📡 Live TV / IPTV (M3U Player)
- **Official Indonesian TV Presets (Out-of-the-Box)**: Preloaded with public legal FTA broadcast channels from Indonesia (TVRI, Kompas TV, Metro TV, CNN Indonesia, CNBC Indonesia, BeritaSatu, TVRI Sport, Rodja TV, RRI Net) with offline fallback.
- **Smart Category Normalizer**: Automatically parses and splits multi-tag genre strings (e.g. delimiters like `;` and `,`) into clean, organized Indonesian categories (*Berita*, *Nasional*, *Hiburan*, *Edukasi*, *Anak-anak*, *Budaya & Gaya Hidup*, *Olahraga*, *Religi*).
- **Real-Time Channel Search**: Instant search bar to filter channels quickly by station name or genre.
- **Dedicated Cinema Live TV Player**:
  - **Auto-Rotate to Landscape**: Automatically rotates and locks mobile devices to immersive landscape mode upon opening any broadcast, and smoothly restores portrait upon exiting.
  - **Quick Remote Zapping**: Press D-pad **Up / Down** on TV remote (or tap controls) to switch channels instantly without interrupting playback.
  - **OSD Side Channel Drawer**: Press **Left / Select** to browse the full channel lineup in a frosted-glass drawer while the broadcast keeps streaming.
  - **Favorites & Categories**: Tag favorite stations for fast access with one click or remote button press.
- **Multi-Playlist Management**: Add, switch, or remove multiple custom M3U/M3U8 playlist URLs easily.

### 8. 🍿 Detail-First, Cinematic User Journey
- **Informative Detail Pages**: No disruptive auto-play. Explore high-res posters, release years, genres, ratings, and plot overviews first.
- **One-Click Hero Play & Resume**: Instant play button automatically selects the **Original Audio** and **Best Available Quality**, with smart resume support if you've watched before.
- **Clean Interface**: No cluttered manual resolution lists on the detail screen—everything is handled effortlessly inside the player.

### 9. 🎛️ Full In-Player Controls
- **On-the-Fly Quality Switcher (`Icons.high_quality`)**: Switch between 4K UHD, 1080p, 720p, and mirrors directly during playback without losing your timestamps (*seamless seek*).
- **Audio Dub Track Switcher (`Icons.audiotrack`)**: Switch between multiple audio language tracks on-the-fly.
- **TV Series Episode Drawer (`Icons.video_library`)**: Browse and jump to any season or episode in a sleek Netflix-style drawer while the video continues playing.
- **Netflix-Style Smart Next Episode**: Compact, transparent glassmorphism countdown popup near the credit roll with remote-focused play and dismiss buttons.

### 10. 🔊 Audio Dubs & Clean Subtitles
- **Multi-Language Audio Dubs**: Supports alternate language tracks when available.
- **Garbage Subtitle Filter**: Automatically filters out spam, bot-generated, and corrupted subtitle files.
- **Cross-Dub Subtitle Sharing**: Subtitles are intelligently shared across dub variants so you never miss translations.

### 11. 🔄 In-App GitHub OTA Auto-Update
- **Automatic & Manual Release Check**: Silently checks for newer releases from GitHub (`kokosip/stream-tv/releases/latest`) on app startup, with manual checking option under the **Settings / Pengaturan** tab.
- **TV & Mobile Update Dialog**: Shows new version tag, release notes, and download size with remote D-Pad navigation.
- **Live Progress & Auto-Install**: Streams APK download with live progress bar and MB counters, automatically launching the Android system package installer on completion.

### 12. 📺 Android TV & Remote Optimization
- **D-Pad First**: Engineered from the ground up for TV remotes with responsive focus scaling, glowing borders, and intuitive navigation.
- **Non-Occluding Navigation & Floating Alerts**: Bottom navigation bar positioned in `Scaffold.bottomNavigationBar` with floating notification toasts ensuring controls never get obstructed.
- **TV PIN Pad Dialog**: Remote-friendly on-screen numeric pad for protected settings and parental controls.
- **Continue Watching & Favorites**: Multi-provider watchlist with playback progress badges and 4K UHD indicators on the home screen.

---

## 🛠️ Technology Stack

- **Framework**: [Flutter](https://flutter.dev/) (Android & Android TV)
- **Playback Engine**: [media_kit](https://github.com/media-kit/media-kit) (High-performance Libmpv hardware-accelerated video & live HLS/M3U8 engine)
- **Live Catalog & Metadata**: [The Movie Database (TMDB) API](https://www.themoviedb.org/) (Real-time cinema & global trending catalog)
- **TV Metadata & Episode Stills**: [TVMaze API](https://www.tvmaze.com/) (Open TV metadata, episode names & still photography)
- **Streaming Sources**: MovieBox API, 4KHDHub Scraper, & M3U/IPTV Streams
- **Typography & Aesthetics**: Google Fonts (`Outfit`), Custom Glassmorphism, Dark Mode Cinema Theme

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (v3.19+ recommended)
- Android TV / Android Box / Emulator or Device running Android 7.0+ (API 24+)

### Installation
1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/stream-tv.git
   cd stream-tv
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your connected Android TV device or emulator:
   ```bash
   flutter run --release
   ```

---

## 👏 Credits & Attributions

- **[The Movie Database (TMDB)](https://www.themoviedb.org/)**: Live cinema box-office now-playing releases, daily/weekly trending movies & TV shows, and high-definition backdrop/poster imagery.
- **[TVMaze](https://www.tvmaze.com/)**: Free TV shows, episode still photography, and series metadata via their public REST API.
- **[MovieBox TUI](https://github.com/mesamirh/MovieBox-Tui)**: Inspiration and foundational research on MovieBox API signatures and endpoints.
- **4KHDHub**: High-resolution movie and series releases.

---

## ⚖️ Disclaimer

> [!IMPORTANT]
> **Client-Side Interface Only**
>
> This software is strictly an open-source, client-side application interface intended for personal use and media browsing on Android TV.
>
> - **We do not host, store, stream, or upload any media or copyright-protected files.**
> - All media links and metadata are retrieved in real-time from third-party publicly available APIs and web scrapers.
> - The developers assume no liability for the content retrieved through third-party services.

