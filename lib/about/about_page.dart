import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/about/about_info.dart';
import 'package:video_player_app/about/about_widgets.dart';
import 'package:video_player_app/about/developer_options.dart';
import 'package:video_player_app/about/github_profile.dart';
import 'package:video_player_app/about/licenses_page.dart';
import 'package:video_player_app/core/slide_snackbar.dart';
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
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
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
                  const _CreatorCard(),
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
                      icon: Icons.code,
                      title: 'Source on GitHub',
                      subtitle: 'github.com/mounsokdara/video-player',
                      link: true,
                      onTap: () => openExternal(AboutInfo.repoUrl),
                    ),
                    AboutItem(
                      icon: Icons.new_releases_outlined,
                      title: 'Releases',
                      subtitle: 'Download the latest APK',
                      onTap: () => openExternal(AboutInfo.releasesUrl),
                    ),
                    AboutItem(
                      icon: Icons.bug_report_outlined,
                      title: 'Report an issue',
                      subtitle: 'Open a GitHub issue',
                      onTap: () => openExternal(AboutInfo.issuesUrl),
                    ),
                    AboutItem(
                      icon: Icons.description_outlined,
                      title: 'Open source licenses',
                      subtitle: 'Libraries used by this app',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicensesPage())),
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
    );
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

class _CreatorCard extends StatefulWidget {
  const _CreatorCard();

  @override
  State<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends State<_CreatorCard> {
  late final Future<GithubProfile?> _profile = GithubProfile.load(AboutInfo.githubLogin);

  Widget _avatar(ColorScheme cs, String? url, String letter) {
    Widget fallback() => Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          child: Text(letter, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onPrimary)),
        );
    if (url == null) return fallback();
    return ClipOval(
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (_, child, p) => p == null ? child : fallback(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AboutSection(
      icon: Icons.person_outline,
      title: 'Created by',
      subtitle: 'Live from GitHub',
      child: FutureBuilder<GithubProfile?>(
        future: _profile,
        builder: (context, snap) {
          final p = snap.data;
          final name = p?.name ?? AboutInfo.author;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _avatar(cs, p?.avatarUrl, name[0].toUpperCase()),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('@${p?.login ?? AboutInfo.githubLogin}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
              FilledButton.tonalIcon(
                onPressed: () => openExternal(AboutInfo.profileUrl),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('GitHub'),
              ),
            ]),
            if (p?.bio != null) ...[
              const SizedBox(height: 14),
              Text(p!.bio!, style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurfaceVariant)),
            ] else if (snap.connectionState != ConnectionState.done) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
          ]);
        },
      ),
    );
  }
}
