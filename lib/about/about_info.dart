/// Single source of truth for the About, Open source licenses and Console pages (all Dart).
class AboutInfo {
  AboutInfo._();

  static const name = 'Video Player';
  static const author = 'Moun Sokdara';
  /// Comes from version.txt: every build passes --dart-define=APP_VERSION=<versionName>.
  static const displayVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');
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
