# MPBG

MPBG is a native macOS SwiftUI app for using local or downloaded videos as `mpv`-powered desktop backgrounds across multiple screens.

It started as a UI around this shell command:

```sh
mpv --border=no --vf=hflip --loop-file=inf --autofit-larger=100%x100% --no-audio --screen=<screen> --speed=<speed> <file>
```

The app keeps that workflow, but adds a library grid, per-screen playback, playlists, live controls, and `yt-dlp` downloads.

## Features

- Native macOS SwiftUI interface.
- Add local video files to a persistent library.
- Play videos as borderless `mpv` backgrounds on a selected screen.
- Run independent videos on different screens.
- Reuse one `mpv` process per screen and switch files through mpv IPC to reduce flicker.
- Live grid controls for speed, loop, horizontal flip, maximize, and sound.
- Videos start muted by default, but can be unmuted live.
- Named playlists assigned to screens.
- Playlist stop controls are screen-scoped, so stopping one playlist does not stop other screens.
- Download tab powered by `yt-dlp` with format selection, audio selection, timestamp ranges, and output folder selection.
- Thumbnail generation using AVFoundation with `ffmpeg` fallback for formats like `.mkv` and `.webm`.

## Requirements

- macOS 13 or newer.
- Swift 6 toolchain / Xcode command line tools.
- [`mpv`](https://mpv.io/) available at `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, or on `PATH` through `/usr/bin/env`.
- Optional for downloads: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) at `/opt/homebrew/bin/yt-dlp`.
- Optional for thumbnails and clipped downloads: [`ffmpeg`](https://ffmpeg.org/) at `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, or `/usr/bin/ffmpeg`.

Homebrew setup:

```sh
brew install mpv yt-dlp ffmpeg
```

## Run From Source

```sh
swift run Mpbg
```

## Build App Bundle

```sh
sh scripts/build-app.sh
open dist/MPBG.app
```

The generated app bundle is intentionally ignored by git. Rebuild it locally when needed.

## Playback Model

Each video card stores:

- Screen index
- Speed
- Loop mode
- Horizontal flip mode
- Maximize mode, not fullscreen
- Volume

MPBG launches `mpv` roughly like this:

```sh
mpv --border=no [--vf=hflip] --loop-file=<inf|no> --autofit-larger=100%x100% --audio=auto --volume=<0-100> --window-maximized=<yes|no> --screen=<screen> --speed=<speed> <file>
```

Live changes are sent over the mpv IPC socket with commands like:

```json
{ "command": ["set_property", "volume", 60] }
```

MPBG creates short `/tmp/mpbg-...sock` socket paths because Unix socket paths have length limits on macOS.

## Playlists

Playlists are named and assigned to screens. Queueing from the Library adds the video to the active playlist for that video's selected screen, creating a default screen playlist if needed.

In the Playlist tab:

- Select a playlist from the sidebar.
- Rename it and assign it to a screen.
- Reorder, remove, clear, or play queued videos.
- Stop only the selected playlist's screen.

## Downloads

The Download tab wraps `yt-dlp`.

Workflow:

1. Paste a URL.
2. Inspect available formats.
3. Choose video and audio quality.
4. Optionally set start and end timestamps.
5. Choose an output folder.
6. Download.

Finished downloads are added to the MPBG library automatically.

## Stored Data

MPBG stores local app data in:

```text
~/Library/Application Support/Mpbg/videos.json
~/Library/Application Support/Mpbg/playlists.json
```

## Development

Run tests:

```sh
swift test
```

The tests include command generation checks and a real mpv IPC socket test.

## License

MIT. See [LICENSE](LICENSE).
