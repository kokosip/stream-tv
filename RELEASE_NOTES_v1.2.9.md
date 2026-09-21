## What's Changed in v1.2.9 🚀

### ✨ New Providers & Streaming Sources
* **Native Dramachi Provider Integration** (`https://api.nodeobjects.com/`):
  * Added native Asian Drama, K-drama, C-drama, and Anime catalog browsing and search.
  * Multi-dub audio routing support (`{titleId}::{rip}`) to easily switch between original voice, English dub, and localized language tracks.
  * Direct byte-range CDN streaming (`direct_file: true`) for ultra-fast, smooth seekable playback without proxy overhead.
  * Seamless integration with search screen, provider filter chips, episode selector, player auto-next, favorites, downloads, and playback progress tracking.

### 🛠️ MovieBox Deprecated API & Stream Extraction Fixes
* **`Edge-Cache-Cookie` DASH Manifest Decoding**: Resolved DASH playback issues by extracting and Base64-decoding `urlprefix=` from `Edge-Cache-Cookie` headers to dynamically reconstruct MPEG-DASH manifests (`index.mpd`).
* **Deprecation Notice Filtering**: Filtered out obsolete deprecation notice MP4 video streams (`macdn.aoneroom.com/other/` and hash `b164fbfb4347792950bdfbfb563d39d9`).
* **Concurrent Server Catalog**: DASH manifests and raw server files are now concurrently resolved, deduplicated by URL base, and sorted by numeric resolution and file size.
* **Audio Track Labeling**: Ambiguous generic `"Dub"` labels are now cleanly sanitized to `"English Dub"`.

### 🔍 4KHDHub & Subtitle Enhancements
* **Enhanced Quality Token Detection**: Added robust resolution token detection (`4K`, `UHD`, `2160`, `1080`, `FHD`, `720`, `HD`, `480`, `SD`) and numeric descending sort for 4KHDHub releases.
* **Clean Subtitle Naming**: Online subtitles now follow clean, standard media naming conventions:
  * TV Episodes: `<Title> - S<SS>E<EE>.srt` (e.g. `Stranger Things - S04E01.srt`)
  * Movies: `<Title>.srt` (e.g. `Inception.srt`)

### 🎬 TMDB Cast & Filmography
* **Cast & Actor Search**: Search actors and crew directly from the TMDB catalog.
* **Cast Filmography Screen**: View complete actor filmography and discover related movies and TV series.
* **Recent Played Progress Bar**: Visual progress indicator on recently played items on the home screen.

### 🐛 Bug Fixes
* Fixed an issue when opening film details directly from the search page without executing a search query.
* Fixed episode auto-progression (`PlayerNextEpisodeData`) in player controls for multi-season providers.

---

**Full Changelog**: https://github.com/kokosip/stream-tv/compare/v1.2.8...v1.2.9
