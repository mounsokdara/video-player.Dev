import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/about/about_info.dart';
import 'package:video_player_app/about/about_widgets.dart';
import 'package:video_player_app/about/developer_options.dart';
import 'package:video_player_app/about/github_profile.dart';
import 'package:video_player_app/about/licenses_page.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/core/widgets.dart';
import 'package:video_player_app/settings/settings.dart';

/// About page, laid out like the Dara Hub site: hero card, section cards and
/// connected rows. Pure Dart (no native activity / XML).
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _tapsNeeded = 10;
  int _taps = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  void _say(String message) =>
      SlideSnackBar.show(context, message: message, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2));

  void _onVersionTap() {
    final now = DateTime.now();
    if (now.difference(_lastTap) > const Duration(seconds: 2)) _taps = 0;
    _lastTap = now;
    _taps++;
    if (appSettings.developerEnabled) {
      _say('Developer options are on');
      return;
    }
    final left = _tapsNeeded - _taps;
    if (left >= 1 && left <= 3) _say('$left tap${left == 1 ? '' : 's'} away from developer options');
    if (_taps >= _tapsNeeded) {
      _taps = 0;
      appSettings.developerEnabled = true;
      appSettings.save();
      HapticFeedback.heavyImpact();
      setState(() {});
      _say('Developer options enabled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = SystemBars.bottomInset(context);
    return SystemBarSafeZone(child: Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(pinned: true, leading: standaloneBack(context), title: const Text('About')),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _Hero(),
                  const SizedBox(height: 12),
                  AboutQuickActions(items: [
                    QuickAction(
                      icon: const Icon(Icons.history),
                      label: 'Changelog',
                      onTap: () => openExternal(AboutInfo.changelogUrl),
                    ),
                    QuickAction(
                      icon: const GithubIcon(),
                      label: 'GitHub',
                      onTap: () => openExternal(AboutInfo.repoUrl),
                    ),
                    QuickAction(
                      icon: const Icon(Icons.new_releases_outlined),
                      label: 'Releases',
                      onTap: () => openExternal(AboutInfo.releasesUrl),
                    ),
                    QuickAction(
                      icon: const Icon(Icons.bug_report_outlined),
                      label: 'Issues',
                      onTap: () => openExternal(AboutInfo.issuesUrl),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Text('Author', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const _AuthorCard(),
                  const SizedBox(height: 12),
                  AboutGroup(items: [
                    AboutItem(
                      icon: Icons.info_outline,
                      title: 'Version',
                      subtitle: AboutInfo.displayVersion,
                      onTap: _onVersionTap,
                      chevron: false,
                    ),
                    AboutItem(
                      icon: Icons.description_outlined,
                      title: 'Open source licenses',
                      subtitle: 'Libraries used by this app',
                      onTap: () => openPage(context, '/licenses', () => const SystemBarSafeZone(child: LicensesPage())),
                    ),
                  ]),
                  if (appSettings.developerEnabled) ...[
                    const SizedBox(height: 12),
                    const DeveloperOptionsSection(),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    ));
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset('assets/logo.png', width: 64, height: 64, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(height: 16),
        Text(AboutInfo.name, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(AboutInfo.tagline, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        const Wrap(spacing: 8, runSpacing: 8, children: [
          AboutChip('v${AboutInfo.displayVersion}', icon: Icons.sell_outlined),
        ]),
      ]),
    );
  }
}

class _AuthorCard extends StatefulWidget {
  const _AuthorCard();

  @override
  State<_AuthorCard> createState() => _AuthorCardState();
}

class _AuthorCardState extends State<_AuthorCard> {
  static const _avatarSize = 112.0;
  late final Future<GithubProfile?> _profile = GithubProfile.load(AboutInfo.githubLogin);

  Widget _avatar(ColorScheme cs, String? url, String letter) {
    Widget fallback() => Container(
          width: _avatarSize,
          height: _avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          child: Text(letter, style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: cs.onPrimary)),
        );
    if (url == null) return fallback();
    return ClipOval(
      child: Image.network(
        url,
        width: _avatarSize,
        height: _avatarSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (_, child, p) => p == null ? child : fallback(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: SizedBox(
          width: double.infinity,
          child: FutureBuilder<GithubProfile?>(
            future: _profile,
            builder: (context, snap) {
              final p = snap.data;
              final name = p?.name ?? AboutInfo.author;
              return Column(children: [
                _avatar(cs, p?.avatarUrl, name[0].toUpperCase()),
                const SizedBox(height: 16),
                Text(name,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(AboutInfo.authorRole,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w400)),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                    child: FilledButton.icon(
                      onPressed: () => openExternal(AboutInfo.supportUrl),
                      icon: const Icon(Icons.volunteer_activism_outlined),
                      label: const Text('Support my work'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'GitHub profile',
                    iconSize: 28,
                    onPressed: () => openExternal(AboutInfo.profileUrl),
                    icon: const GithubIcon(size: 28),
                  ),
                  if (AboutInfo.contactEmail.isNotEmpty)
                    IconButton(
                      tooltip: 'Email',
                      iconSize: 28,
                      onPressed: () => openExternal('mailto:${AboutInfo.contactEmail}'),
                      icon: const Icon(Icons.mail_outline),
                    ),
                ]),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
