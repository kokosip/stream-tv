## What's Changed in v1.2.11 🎬

This release introduces **SubDL Subtitle Integration** with multi-key failover, **Direct Instant Playback** from Watch History, and major fixes for **MovieBox Series & TV Show playback**.

### ✨ New Features & Enhancements
* **SubDL Subtitle Provider & Failover Pool**:
  - Integrated SubDL as a concurrent subtitle provider alongside OpenSubtitles.
  - Added a 3-key API pool with automatic failover and cooldown rotation to prevent daily rate-limit issues.
  - Added in-memory ZIP archive decompression for SubDL subtitle downloads for both movies and specific TV show episodes (`E01`, `EP01`, etc.).
  - Configurable via Firebase Remote Config (`subdl_api_key`).
* **Direct Play from Watch History**:
  - Tapping the **Play Button** or **Poster Thumbnail** in the Watch History tab immediately resolves streams and opens the video player.
  - Tapping the **Title / Details** area opens the detail screen for browsing synopsis, cast, and seasons.
* **Separated Actions for TV & Mobile Controls**:
  - Full D-Pad / Remote control focus navigation support on History items: Info card, Play button, and Delete button are independently focusable.

### 🐛 Bug Fixes & Stability Improvements
* **Fixed Series Detail TMDB 404 Error**:
  - Prevented 64-bit MovieBox series IDs from incorrectly triggering TMDB endpoints (`/tv/<id>`).
  - Added multi-dub track season resolution to correctly fetch season & episode lists for titles where parent containers report 0 seasons (e.g., *The Ordinary Jackpot*).
* **Safe Season & Episode Parsing**:
  - Hardened episode counts (`maxEp`) and season number parsing across all media providers to eliminate runtime type cast exceptions (`TypeError`).
* **Self-Healing Watch History Records**:
  - Automatically heals existing watch history entries where MovieBox items were saved under the `tmdb` provider prefix.

---

**Full Changelog**: https://github.com/kokosip/stream-tv/compare/v1.2.10...v1.2.11
