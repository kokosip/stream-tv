## What's Changed in v1.2.10 🚑

This is a hotfix release resolving issues with deprecated/notice video playback streams and improving stream resolution stability.

### 🐛 Hotfixes & Stream Extraction Improvements
* **Deprecated Video Notice Filtering**: Fixed an issue where obsolete server notice videos (`macdn.aoneroom.com/other/` & `b164fbfb4347792950bdfbfb563d39d9`) were shown instead of real movie/episode streams.
* **Edge-Cache MPEG-DASH Recovery**: Added support for decoding `urlprefix=` inside `Edge-Cache-Cookie` headers, dynamically reconstructing working MPEG-DASH (`index.mpd`) stream manifests when standard CloudFront policies are unavailable.
* **Stream Catalog Deduplication & Sorting**: Concurrently merged raw server files and DASH manifest streams, filtering out duplicate URLs and sorting releases by descending resolution and file size for the best playback quality.

---

**Full Changelog**: https://github.com/kokosip/stream-tv/compare/v1.2.9...v1.2.10
