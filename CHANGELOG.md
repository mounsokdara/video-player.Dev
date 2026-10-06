# Changelog

## Unreleased (dev)

Navigation bar:
- No hardcoded navigation bar color any more: the app no longer forces it transparent (themes, native window setup, Flutter overlay style) and no longer paints its own solid strip over it; the system default is used, with the system contrast scrim
- Pages still keep their content clear of the bar; the snackbar no longer overlaps the navigation buttons

About:
- New layout: a row of quick actions (Changelog, GitHub, Releases, Issues) and an Author card with avatar, name, role, "Support my work", GitHub profile and (optional) mail buttons

Equalizer:
- Large screens (720 dp and wider): two-pane layout with taller band sliders and a dB ruler on the left, presets and bass / surround in side cards, centred with a maximum width
- Each band shows its current dB value; phones keep the single column (capped width on tall tablets)

Settings:
- Screens that have their own activity (Settings categories, About, Equalizer, Open source licenses, Console) always open as that activity with the system slide transition, like Settings from the More tab; if an activity is unavailable the in-app page is used. The player's own Equalizer button stays in-app (opening an activity there would trigger picture-in-picture)
- The equalizer is re-applied when the app resumes, so changes made in its activity take effect

Tabs:
- Switching between Videos / Folders / More (bottom bar and large-screen rail) now slides and fades in the direction of the tab, instead of an instant swap

Ripple:
- Developer options switches, the GitHub button in the About page and the Equalizer card rows now show their ripple (the cards are Material surfaces instead of decorated containers that hid it)

Cleanup:
- Removed the unused package_info_plus dependency

System navigation bar:
- No more black bar where the navigation bar is while a page (for example Settings) slides in: the status / navigation bars are transparent from the moment the window is created (themes + early edge-to-edge setup), with no contrast scrim
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
