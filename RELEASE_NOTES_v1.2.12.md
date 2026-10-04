## What's Changed in v1.2.12 🚀

This major release integrates **8 New Streaming Media Providers** reverse-engineered from Cloudstream (`xr3ed-Repo`), introduces built-in **DNS-over-HTTPS (DoH)** network resolution to bypass ISP filtering, and delivers unified **Multi-Source Search & Stream Bridging** across the entire app.

---

### ✨ Major Features & Enhancements

#### 🎬 8 New Dedicated Streaming Providers
* **PusatFilm Integration**:
  - Full catalog of Indonesian & Hollywood movies and TV series.
  - Reverse-engineered custom XOR cipher decryption (`pfilms` key) with anti-bot bypass and direct player iframe resolution.
* **JuraganFilm Integration**:
  - Extensive Asian dramas, Hollywood releases, and Indonesian films.
  - Deobfuscated Supervideo player extractor with direct MP4 and HLS stream resolution.
* **Samehadaku Integration**:
  - Premier Indonesian anime streaming platform.
  - Automated HTML scraper with Blogger and multi-mirror video frame extractors.
* **Otakudesu Integration**:
  - Comprehensive anime catalog sub Indo.
  - Automated AJAX nonce resolver (`action: post`) and embedded stream unpacker.
* **Anichin Integration**:
  - Top Donghua (Chinese 3D Animation) portal.
  - Multi-server mirror scraper with direct video stream extraction.
* **DracinSI Integration**:
  - Dedicated Chinese drama (C-Drama) portal sub Indo.
  - Direct video embed parsing and CDN MP4 stream extractors.
* **DrakorKita Integration**:
  - Premier Korean drama (K-Drama) hub.
  - Inlined base64 script deobfuscator and direct high-speed video streams.
* **SoraStream Aggregator Integration**:
  - Universal multi-source streaming aggregator with TMDB metadata bridging.
  - Multi-server fallback engine including VidSrc, SuperEmbed, 2Embed, and SmashyStream.

#### 🛡️ Built-in DNS-over-HTTPS (DoH) Client
* Integrated **Cloudflare DoH** (`https://cloudflare-dns.com/dns-query`) and **Google DoH** fallback into `SafeHttpClient`.
* Transparently bypasses ISP DNS filtering and censorship (e.g., Indonesian ISP blocks on streaming websites) without requiring external VPNs.

#### 🔍 Unified Multi-Source Search & Interleaved Results
* Updated **SearchScreen** with dynamic provider filter chips:
  - `All`, `MovieBox`, `4KHDHub`, `PusatFilm`, `JuraganFilm`, `Samehadaku`, `Otakudesu`, `Anichin`, `DracinSI`, `DrakorKita`, `SoraStream`.
* Concurrently queries all active providers and interleaves results fairly for a balanced, rich discovery experience.
* Added high-contrast visual badges and custom brand colors for each provider.

#### ⚡ Multi-Source Detail & Stream Resolver Engine
* Seamless routing in `DetailScreen` for synopsis, cast, season/episode trees, and posters across all 8 new providers.
* Multi-source stream bridging allows viewers to effortlessly select or fallback between different source mirrors.
* `PlayerScreen` dynamically applies custom HTTP headers (`Referer`, `Origin`, `User-Agent`) required by strict CDN media servers.

---

### 🐛 Bug Fixes & Stability Improvements
* **Regex & String Literal Hardening**: Fixed raw string quote terminations and pattern matching across scraper engines.
* **Type-Safe Season & Episode Parsing**: Resolved potential `TypeError` crashes during season navigation and episode clamping.
* **Cleaned Up Unused Imports & Lint Cleanliness**: Zero compilation errors across all services and screens.

---

**Full Changelog**: https://github.com/kokosip/stream-tv/compare/v1.2.11...v1.2.12
