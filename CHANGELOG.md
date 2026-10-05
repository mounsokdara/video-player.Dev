# Changelog

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
