class AboutInfo {
  AboutInfo._();

  static const name = 'Video Player';
  static const author = 'Moun Sokdara';
  static const displayVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');
  /// Android versionCode (the number after "+" in version.txt), passed in at build time.
  static const buildNumber = String.fromEnvironment('APP_BUILD', defaultValue: '');
  /// "1.0.4 (13)" when the build number is known, otherwise just "1.0.4".
  static const displayVersionWithCode =
      buildNumber == '' ? displayVersion : '$displayVersion ($buildNumber)';
  static const tagline = 'Local-only Material 3 player. Your videos never leave the device.';

  static const githubLogin = 'mounsokdara';
  static const profileUrl = 'https://github.com/$githubLogin';
  static const repoSlug = '$githubLogin/video-player';
  static const repoUrl = 'https://github.com/$repoSlug';
  static const releasesUrl = '$repoUrl/releases';
  static const issuesUrl = '$repoUrl/issues';

  static const authorRole = 'Lead Developer';

  static const supportUrl = 'https://github.com/sponsors/$githubLogin';

  static const contactEmail = '';
}
