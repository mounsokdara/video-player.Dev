# Changelog

## Unreleased (dev)

Navigation bar:
- Fix: the system navigation bar is now always transparent with no system scrim or default color (native window, themes and Flutter overlay), so the only thing you see behind the buttons is the app's solid strip: no gray tint on the home screen, same look on every screen and Android version, no white flash when another activity opens
- Fix: the strip now dims together with dialogs and sheets (it blends the open popup's barrier color) instead of staying bright under them
- Player: the navigation bar is solid in the watch layout (not full screen) and transparent only in full screen; the home tabs' strip now continues the bottom navigation bar color instead of the page surface
- Fix: outside the player the navigation bar is solid again (app surface color). On Android 15+ the system ignores `navigationBarColor`, so a solid strip is painted behind the bar; the player still keeps it fully transparent
- In the player (full screen, sheets and dialogs included) the navigation bar is fully transparent, no scrim; leaving the player returns to the system default
- No hardcoded navigation bar color any more: the app no longer forces it transparent (themes, native window setup, Flutter overlay style) and no longer paints its own solid strip over it; the system default is used, with the system contrast scrim
- Pages still keep their content clear of the bar; the snackbar no longer overlaps the navigation buttons

About:
- Quick-action tiles are all the same height and the GitHub mark is sized like the other icons
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

Fixed:
- Seek bar thumb no longer flips between old and new positions during scrub
- Thumb no longer snaps back after release
- Preview no longer pushes seek bar and time labels around
- Portrait video preview no longer shows pixelated landscape crop
- Preview frames no longer blink when swapping
- Android nav bar no longer draws opaque gray strip
- Mini player no longer clips off left edge and overlaps grid
- Long press action sheet no longer cuts off in landscape
- Mini card no longer shows VIDEO LOG debug text
- Bottom sheet no longer scrolls too far
- Library tabs no longer scroll when there is nothing inside them

Added:
- Floating preview overlay centered on thumb
- Preview frames at real aspect ratio and screen density
- JPEG quality 85
- Last good preview frame fallback
- More tab in bottom bar and side rail
- Settings entry in More tab
- Equalizer, Crash report and About entries
- SettingsActivity in manifest
- Large screen sidebar at 840 dp and up
- 16:10 thumbnails
- Up to 8 columns on wide screens
- Wide header row for count filters and grid sort buttons
- Launchable activity in each page instead of one main activity

Improved:
- Preview box matches frame shape with no cropping
- Engine ignores stale mpv positions until playback settles within 1.2 seconds
- Slider release and swipe seek use same immediate seek target
- Tablet grid uses real content width instead of whole screen width
- Landscape tablet grid shows 4 columns instead of 3
- Visible rows increase from about half a row to about 1.5 rows
- Mini player parked state clipped to content area
- Expand chevron stays at content edge
- System Nav bar only transparent on library and player when not fullscreen
- Fullscreen video still hides bars
- Settings screen reloads changes after returning
- Phones in portrait keep same two column cards
- Page improvements
- Better equalizer layout

Changed:
- Settings tab replaced by More tab in bottom bar and side rail
- Nav bar contrast enforcement turned off in Dart and native
- Contrast enforcement off for popups too
- Seek now jumps to nearest keyframe
- Grid columns based on available content width
- Wide content header shares one row

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
