# Changelog

## 1.0.2.4

Mini player:
- Sizes and positions itself from the real content area instead of the full screen and a guessed 88 px nav height, so it never overlaps or hides behind the bottom navigation bar on any device or system-bar style
- Even 16 px margin on all sides, matching the page padding; side insets are no longer applied twice in landscape
- Wide / landscape layout: the mini player stays in the content area and can no longer park over the navigation rail
- Maximum size recalculated for the real area (bigger on tall screens, never taller than the area) and can no longer crash on very short windows
- Narrow card: the clipped title is dropped and the three buttons are spread evenly across the bar; buttons are slightly larger and shrink only when the card is very small

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
