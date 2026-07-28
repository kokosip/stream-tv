# StreamTV (MovieBox TV Client)

A premium, TV-optimized Flutter application designed for Android and Android TV devices to stream movies and TV series.

## Features

- **TV Focusable UI**: Fully compatible with Android TV remote controllers (D-Pad navigation).
- **Search**: Search for any movie or TV show.
- **Dubs & Subtitles**: Easily switch audio language tracks and toggle external subtitles.
- **Interactive Player**: Upgraded with a seekable progress bar (drag-to-seek) and remote control shortcuts (back, play/pause, rewind, fast forward).
- **Favorites / Quick Access**: Bookmark your favorite movies and series directly to the Home screen for quick access.
- **Stream Selector**: Multi-resolution options (up to 1080p) sorted dynamically by resolution and codecs (AVC prioritized over HEVC for wider compatibility).

## Credits

- Special thanks and credit to the creator of the [MovieBox TUI](https://github.com/mesamirh/MovieBox-Tui) and its underlying backend API services.

## Disclaimer

> [!IMPORTANT]
> **Client-Side Only Disclaimer**
>
> This application is strictly a **client-side wrapper/interface** designed to improve the viewing experience on Android TV.
>
> - **We do not host, store, or upload any movies, TV shows, or videos.**
> - All media files and streams are accessed directly from third-party public API providers.
> - The application only fetches and parses media links for streaming.

## Getting Started

To run this application locally, ensure you have the Flutter SDK installed and a device connected.

1. Clone this repository.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run --release
   ```
