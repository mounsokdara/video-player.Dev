# Changelog

## Unreleased (dev)

Equalizer:
- Large screens (720 dp and wider): two-pane layout with taller band sliders and a dB ruler on the left, presets and bass / surround in side cards, centred with a maximum width
- Each band shows its current dB value; phones keep the single column (capped width on tall tablets)

System navigation bar:
- Bottom sheets now end above the navigation bar instead of scrolling under it, so the last action (for example Properties) is never covered by the bar buttons
- About and Open source licenses pages keep clear of the side / bottom bar and cutouts

## 1.0.2.3

Performance:
- Playback progress now saves one small key instead of rewriting every setting every 4 seconds, and skips the write when nothing changed
- Settings saves are merged so overlapping saves no longer pile up
- Thumbnails: capped memory cache, at most 3 loads at once, duplicate requests share one load, and a thumbnail can no longer land on the wrong row after fast scrolling
- The player clock and battery timer no longer rebuild the page when the clock and battery are hidden

## 1.0.2.2

Fix:
- Player no longer opens the same video several times at once
- Closing the player while a video is still loading no longer disposes the engine mid-open
- Quick repeated taps on the same video are ignored

## 1.0.2.1

Small change:
- Added a better snackbar instead of the long, wide default snackbar

Fix (mini player):
- Stays clear of the bottom navigation bar on every device and system-bar style; the guessed nav height is gone and the real content area is used
- Even 16 px margin on all sides, matching the page padding; side insets are no longer counted twice in landscape
- Wide / landscape: stays in the content area and no longer parks over the navigation rail
- Maximum size is calculated from the real area, and a crash on very short windows is fixed
- Narrow card: the clipped title is dropped and the three buttons spread evenly; buttons are a little larger
