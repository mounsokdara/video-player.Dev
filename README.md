<!--
  DEV WORKFLOW NOTE (hidden):
  This is the DEV copy of mounsokdara/video-player.
  Make and test every change HERE first (branch dev/** or main), confirm the
  Dev Test workflow passes and the dev APK works, and only then publish the
  change to the public repo. Never edit the public repo directly without a deep testing
-->
> **Dev/test copy** of [mounsokdara/video-player](https://github.com/mounsokdara/video-player).this repo workflow only for analyze and build a test APK, no releases are published. unless you have a full copy of this

# Video Player

Local-only Material 3 Android player. Playback uses libmpv. Files stay on the device.

[Download APK][download]

[download]: https://github.com/mounsokdara/video-player/releases/latest/download/com.mounsokdara.video_player.apk

## Library

- Scans internal storage, SD cards, USB / OTG drives
- Optional hidden files
- Auto-refresh when videos are added, changed, or deleted
- Scan on start (optional)
- Videos tab: list or grid, search, filters, All, Bookmarked, Pinned
- Sort by name, date, size, duration, or folder (ascending or descending)
- Tap anywhere on a video row to open; checkbox is on the right while selecting
- Hold a clip for actions
- Folders tab: browse volumes folders, hold for play queue / copy / cut / share / bookmark / pin / delete / properties
- Rename only when a single item is selected
- Copy cut, paste is a bottom-right button clears after one paste
- Confirm before delete
- Resume bar on thumbnails
- Bookmarks pins
- Pull to refresh
- Hide Videos, Folders, or Settings from the bottom bar

## Open from other apps

- Open a video with Video Player `VIEW` / `SEND`
- USB device attached is recognized
- Other apps’ Open-from / Get content / Pick launches the in-app video picker
- One video at a time

## Player

- libmpv playback, one video at a time
- Hardware, software, or auto decoder
- Player style:
  - Bottom dialog sheet: fullscreen player, playlist as a Material sheet
  - YouTube watch page: video, details under the frame, list on the right in landscape; scroll to resize the frame; animated maximize / minimize
- Play modes: Order, Loop all, Repeat current, Shuffle all, No autoplay
- Auto play next
- Resume from last position
- Speed with optional pitch shift
- Long press 2×
- Double-tap seek
- Exclusive gestures: pinch zoom, or one-finger seek / brightness / volume — not at the same time
- Pinch zoom; zoom resets when minimizing
- Screen modes: Fit, Zoomed full screen, Original size, Stretch, 16:9, 4:3, 21:9, 2.35:1, 1:1, 9:16
- Rotation: none, sensor auto, auto to video, lock landscape / portrait each direction
- HUD only with the player controls
- Customizable title-bar buttons, quick actions, floating action buttons
- Screenshot
- Share, bookmark, delete, properties
- A-B repeat
- Sleep timer
- Lock controls
- Mirror, invert, night mode, extra dim
- Color correction: contrast, saturation, gamma, hue
- Always-hide navigation bar, or bars follow the controller
- Material 3 ripples on double-tap seek

## Mini player background

- In-app mini player scales to the screen, 16:9 landscape or 9:16 portrait
- Stays inside the content area: clear of the bottom navigation bar and the side rail, with an even 16 px margin
- Narrow card shows only previous / play / next, evenly spaced
- Pinch to resize, park to an edge, swipe down to close
- Quick gestures disabled while minimized
- Picture-in-picture
- Background play with a music-style notification
- Pause stays paused when you leave come back
- Optional remember background play for every video

## Audio

- Ten-band equalizer
- Presets: Flat, Bass, Treble, Vocal, Rock, Pop, Jazz, Classical, Dance, Electronic
- Bass boost surround
- Left / right balance
- Volume brightness overlays while gesturing
- Audio focus ducking

## Theme accessibility

- Light, dark, or system
- Dynamic color from the wallpaper; seed color picker greys out while that is on
- High contrast, grayscale, invert, night mode, extra dim
- Deuteranopia, protanopia, tritanopia filters
- Reduce motion, large controls, bold text, focus highlight
- Interface scale
- Haptic feedback

## System

- All-files access for deletes, renames, hidden-folder scans
- Crash report
- Developer options: debug log console
- Open-source licenses
- Created by Moun Sokdara
