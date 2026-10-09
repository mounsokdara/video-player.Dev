/// Single source of truth for the About, Open source licenses and Console pages (all Dart).
class AboutInfo {
  AboutInfo._();

  static const name = 'Video Player';
  static const author = 'Moun Sokdara';
  static const displayVersion = '1.0.3.1';
  static const tagline = 'Local-only Material 3 player. Your videos never leave the device.';

  static const githubLogin = 'mounsokdara';
  static const profileUrl = 'https://github.com/$githubLogin';
  static const repoSlug = '$githubLogin/video-player';
  static const repoUrl = 'https://github.com/$repoSlug';
  static const releasesUrl = '$repoUrl/releases';
  static const issuesUrl = '$repoUrl/issues';

  /// Shown under the author's name.
  static const authorRole = 'Lead Developer';

  /// Target of the "Support my work" button.
  static const supportUrl = 'https://github.com/sponsors/$githubLogin';

  /// Address behind the mail button. Leave empty to hide the button.
  static const contactEmail = '';
}
