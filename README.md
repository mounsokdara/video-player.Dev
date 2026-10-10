<!--
  DEV WORKFLOW NOTE (hidden):
  This is the DEV copy of mounsokdara/video-player.
  Make and test every change HERE first (branch dev/** or main), confirm the
  Dev Test workflow passes and the dev APK works, and only then publish the
  change to the public repo. Never edit the public repo directly without a deep testing
-->
> **Dev/test copy** of [mounsokdara/video-player](https://github.com/mounsokdara/video-player).this repo workflow only for analyze and build a test APK, no releases are published. unless you have a full copy of this

# Video Player

Local-only Material 3 Android player. Playback uses libmpv (media_kit). Files stay on the device.

[Download APK](https://github.com/mounsokdara/video-player/releases/latest/download/com.mounsokdara.video_player.apk)

## Library

- Scans internal storage, SD cards, and USB / OTG drives
- Optional hidden files (dot-folders and hidden videos)
- Auto-refresh when videos are added, changed, or deleted
- Scan on start (optional)
- Videos tab: list or grid, search, filters, All, Bookmarked, Pinned
- Sort by name, date, size, duration, or folder (ascending or descending)
- Tap anywhere on a video row to open; checkbox is on the right while selecting
- Hold a clip for actions (no 3-dot on list rows)
- Folders tab: browse volumes and folders, hold for play queue / copy / cut / share / bookmark / pin / delete / properties
- Rename only when a single item is selected
- Copy and cut; paste is a bottom-right button and clears after one paste
- Confirm before delete (optional)
- Resume bar on thumbnails
- Bookmarks and pins
- Pull to refresh
- Hide Videos, Folders, or Settings from the bottom bar (at least one tab stays; hidden tabs move to the overflow menu)

## Open from other apps

- Open a video with Video Player (`VIEW` / `SEND`)
- USB device attached is recognized
- Other apps’ Open-from / Get content / Pick launches the in-app video picker (v1.0.1)
- One video at a time (a second open replaces the current one)

## Player

- libmpv playback, one video at a time
- Hardware, software, or auto decoder (HW priority optional)
- Player style:
  - Bottom dialog sheet (default): fullscreen player, playlist as a Material sheet
  - YouTube watch page: video, details under the frame, list on the right in landscape; scroll to resize the frame (16:9 or up to 9:16); animated maximize / minimize
- Play modes: Order, Loop all, Repeat current, Shuffle all, No autoplay
- Auto play next (Order mode)
- Resume from last position
- Speed with optional pitch shift (off = no chipmunk audio)
- Long press 2× (optional haptic)
- Double-tap seek (step 5–30 seconds)
- Exclusive gestures: pinch zoom, or one-finger seek / brightness / volume — not at the same time
- Pinch zoom (optional); zoom resets when minimizing
- Screen modes: Fit, Zoomed full screen, Original size (native pixels, never upscale), Stretch, 16:9, 4:3, 21:9, 2.35:1, 1:1, 9:16
- Rotation: none, sensor auto, auto to video, lock landscape / portrait and each direction
- HUD (clock, battery, remaining time) only with the player controls
- Customizable title-bar buttons, quick actions, and floating action buttons
- Screenshot (saved to DCIM / Screenshots)
- Share, bookmark, delete, properties (path, size, duration, resolution, fps, bitrate, container, MIME, timestamps)
- A-B repeat
- Sleep timer
- Lock controls
- Mirror, invert, night mode, extra dim
- Color correction: contrast, saturation, gamma, hue
- Always-hide navigation bar, or bars follow the controller
- Material 3 ripples on double-tap seek

## Mini player and background

- In-app mini player scales to the screen, 16:9 landscape or 9:16 portrait
- Stays inside the content area: clear of the bottom navigation bar and the side rail, with an even 16 px margin
- Narrow card shows only previous / play / next, evenly spaced
- Pinch to resize, park to an edge, swipe down to close
- Quick gestures disabled while minimized
- Picture-in-picture (system PIP)
- Background play with a music-style notification (play, pause, skip)
- Pause stays paused when you leave and come back
- Optional remember background play for every video

## Audio

- Ten-band equalizer (31 Hz–16 kHz)
- Presets: Flat, Bass, Treble, Vocal, Rock, Pop, Jazz, Classical, Dance, Electronic
- Bass boost and surround
- Left / right balance
- Volume and brightness overlays while gesturing
- Audio focus and ducking

## Theme and accessibility

- Light, dark, or system
- Dynamic color from the wallpaper (Material You); seed color picker greys out while that is on
- High contrast, grayscale, invert, night mode, extra dim
- Deuteranopia, protanopia, tritanopia filters
- Reduce motion, large controls, bold text, focus highlight
- Interface scale
- Haptic feedback
- Live Caption (Settings > Accessibility): AI captions of the spoken words while a video plays, fully offline, extracted phrase by phrase as spoken with progress shown, and cached per video so replays are instant. Quick toggle and shortcut in the player's More sheet. The speech engine and Whisper models (Base or Small) are downloaded from Manage AI model, with default model and language settings

## System

- All-files access for deletes, renames, and hidden-folder scans
- Crash report (copy last error)
- Developer options (tap version 10 times): debug log and console
- Open-source licenses
- Created by Moun Sokdara
