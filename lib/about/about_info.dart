/// Single source of truth for the About page.
/// Keep [displayVersion] in sync with AboutInfo.VERSION in NativeConstants.kt
/// (only the native Open source licenses page still reads that copy).
class AboutInfo {
  AboutInfo._();

  static const name = 'Video Player';
  static const author = 'Moun Sokdara';
  static const displayVersion = '1.0.2.3';
  static const tagline = 'Local-only Material 3 player. Your videos never leave the device.';

  static const profileUrl = 'https://github.com/mounsokdara';
  static const repoUrl = 'https://github.com/mounsokdara/video-player';
  static const releasesUrl = '$repoUrl/releases';
  static const issuesUrl = '$repoUrl/issues';
}
