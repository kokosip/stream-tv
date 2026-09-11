# StreamTV (MovieBox & 4KHDHub TV Client)

A premium, cinema-grade Flutter streaming application designed specifically for **Android TV** and **Android** devices. Built for an effortless 10-foot viewing experience with full D-Pad remote control support.

---

## 🌟 Key Features

### 1. 🎬 Multi-Provider Streaming Engine
- **MovieBox API**: Stream thousands of global movies and TV series with multiple audio dubs and subtitle tracks.
- **4KHDHub Integration (4K UHD & 1080p REMUX)**:
  - Access ultra-high-definition releases up to **4K UHD (2160p REMUX, HDR10, Dolby Vision)** and **1080p 10-Bit**.
  - Dynamic HubCloud CDN mirror resolver with smart fallback and preflight byte-range probing to guarantee working stream links.
- **Multi-Provider Search**: Search MovieBox and 4KHDHub simultaneously with provider filter chips and clear visual badges (`[4KHDHub]` and `[MovieBox]`).

### 2. 📺 TVMaze API Metadata Catalog
- **Rich TV Series Metadata**: Integrated with the open **[TVMaze API](https://www.tvmaze.com/)** to enrich TV series cataloging.
- **16:9 Episode Still Thumbnails**: Each episode card showcases the official scene still shot instead of a generic show poster.
- **Official Episode Names & Synopses**: Displays genuine episode titles (e.g., *"Glorious Purpose"*, *"Winter is Coming"*) and full plot summaries cleanly stripped of HTML formatting.
- **Gold Star Episode Ratings**: Highlights community ratings directly on the episode cards.
- **In-Memory Caching & Title Normalizer**: Automatically handles show name variations and caches responses to keep navigation blazing fast.

### 3. 📡 Live TV / IPTV (M3U Player)
- **Official Indonesian TV Presets (Out-of-the-Box)**: Preloaded with public legal FTA broadcast channels from Indonesia (TVRI, Kompas TV, Metro TV, CNN Indonesia, CNBC Indonesia, BeritaSatu, TVRI Sport, Rodja TV, RRI Net) with offline fallback.
- **Smart Category Normalizer**: Automatically parses and splits multi-tag genre strings (e.g. delimiters like `;` and `,`) into clean, organized Indonesian categories (*Berita*, *Nasional*, *Hiburan*, *Edukasi*, *Anak-anak*, *Budaya & Gaya Hidup*, *Olahraga*, *Religi*).
- **Real-Time Channel Search**: Instant search bar to filter channels quickly by station name or genre.
- **Dedicated Cinema Live TV Player**:
  - **Auto-Rotate to Landscape**: Automatically rotates and locks mobile devices to immersive landscape mode upon opening any broadcast, and smoothly restores portrait upon exiting.
  - **Quick Remote Zapping**: Press D-pad **Up / Down** on TV remote (or tap controls) to switch channels instantly without interrupting playback.
  - **OSD Side Channel Drawer**: Press **Left / Select** to browse the full channel lineup in a frosted-glass drawer while the broadcast keeps streaming.
  - **Favorites & Categories**: Tag favorite stations for fast access with one click or remote button press.
- **Multi-Playlist Management**: Add, switch, or remove multiple custom M3U/M3U8 playlist URLs easily.

### 4. 🍿 Detail-First, Cinematic User Journey
- **Informative Detail Pages**: No disruptive auto-play. Explore high-res posters, release years, genres, ratings, and plot overviews first.
- **One-Click Hero Play & Resume**: Instant play button automatically selects the **Original Audio** and **Best Available Quality**, with smart resume support if you've watched before.
- **Clean Interface**: No cluttered manual resolution lists on the detail screen—everything is handled effortlessly inside the player.

### 5. 🎛️ Full In-Player Controls
- **On-the-Fly Quality Switcher (`Icons.high_quality`)**: Switch between 4K UHD, 1080p, 720p, and mirrors directly during playback without losing your timestamps (*seamless seek*).
- **Audio Dub Track Switcher (`Icons.audiotrack`)**: Switch between multiple audio language tracks on-the-fly.
- **TV Series Episode Drawer (`Icons.video_library`)**: Browse and jump to any season or episode in a sleek Netflix-style drawer while the video continues playing.
- **Netflix-Style Smart Next Episode**: Compact, transparent glassmorphism countdown popup near the credit roll with remote-focused play and dismiss buttons.

### 6. 🔊 Audio Dubs & Clean Subtitles
- **Multi-Language Audio Dubs**: Supports alternate language tracks when available.
- **Garbage Subtitle Filter**: Automatically filters out spam, bot-generated, and corrupted subtitle files.
- **Cross-Dub Subtitle Sharing**: Subtitles are intelligently shared across dub variants so you never miss translations.

### 7. 🔄 In-App GitHub OTA Auto-Update
- **Automatic & Manual Release Check**: Silently checks for newer releases from GitHub (`kokosip/stream-tv/releases/latest`) on app startup, with manual checking option under the **Settings / Pengaturan** tab.
- **TV & Mobile Update Dialog**: Shows new version tag, release notes, and download size with remote D-Pad navigation.
- **Live Progress & Auto-Install**: Streams APK download with live progress bar and MB counters, automatically launching the Android system package installer on completion.

### 8. 📺 Android TV & Remote Optimization
- **D-Pad First**: Engineered from the ground up for TV remotes with responsive focus scaling, glowing borders, and intuitive navigation.
- **TV PIN Pad Dialog**: Remote-friendly on-screen numeric pad for protected settings and parental controls.
- **Continue Watching & Favorites**: Multi-provider watchlist with playback progress badges and 4K UHD indicators on the home screen.

---

## 🛠️ Technology Stack

- **Framework**: [Flutter](https://flutter.dev/) (Android & Android TV)
- **Playback Engine**: [media_kit](https://github.com/media-kit/media-kit) (High-performance Libmpv hardware-accelerated video & live HLS/M3U8 engine)
- **Media Catalog**: [TVMaze API](https://www.tvmaze.com/) (Open TV Metadata & Episode Stills)
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
