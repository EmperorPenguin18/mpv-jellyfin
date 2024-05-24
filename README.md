# mpv-jellyfin
[mpv](https://github.com/mpv-player/mpv) plugin that turns it into a [Jellyfin](https://jellyfin.org/) client

## Features

- Minimal Jellyfin client that integrates into mpv
- Navigate your libraries and play files
- Some basic metadata is shown for each item
- If an item is unwatched, it's description is hidden to prevent spoilers
- When a video file finishes playing, it will be marked as watched

## Installation

Copy the .lua file in `scripts/` to your mpv scripts directory (See [mpv's manual](https://mpv.io/manual/master/#files)).

## Configuration

Can be configured through the usual `script-opts` mechanism of mpv (see its [manual](https://mpv.io/manual/master/#files)). The file [`jellyfin.conf`](script-opts/jellyfin.conf) in this repository contains a detailed list of options.

## Usage

By default, the Jellyfin menu can be toggled with `ctrl+j`.

You can navigate around using the arrow keys.

When you activate a video in the menu, it will begin to play that file.

## Limitations

In general this is a very minimal script and isn't designed to be a full Jellyfin client. Changing settings or metadata has to be done from a real Jellyfin client.

Thumbnails will accumulate if the selected image path isn't tmpfs. In addition thumbnails are raw bgra, which means they are less space efficient than the source images from the Jellyfin server.
