import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/about/about_info.dart';
import 'package:video_player_app/about/about_widgets.dart';
import 'package:video_player_app/about/developer_options.dart';
import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/native/android_bridge.dart';
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
        const SliverAppBar(pinned: true, title: Text('About')),
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
                      onTap: () => AndroidBridge.openPage('licenses'),
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
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
          child: Icon(Icons.play_circle_fill, size: 36, color: cs.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(AboutInfo.name, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(AboutInfo.tagline, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        const Wrap(spacing: 8, runSpacing: 8, children: [
          AboutChip('v${AboutInfo.displayVersion}', icon: Icons.sell_outlined),
          AboutChip('Material 3', icon: Icons.palette_outlined),
          AboutChip('libmpv', icon: Icons.movie_outlined),
        ]),
      ]),
    );
  }
}

class _CreatorCard extends StatelessWidget {
  const _CreatorCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AboutSection(
      icon: Icons.person_outline,
      title: 'Created by',
      subtitle: 'Design and development',
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          child: Text(AboutInfo.author[0],
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onPrimary)),
        ),
        const SizedBox(width: 14),
        const Expanded(child: Text(AboutInfo.author, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        FilledButton.tonalIcon(
          onPressed: () => openExternal(AboutInfo.profileUrl),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('GitHub'),
        ),
      ]),
    );
  }
}
