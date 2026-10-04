import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/core/crash.dart';
import 'package:video_player_app/core/developer_log.dart';
import 'package:video_player_app/settings/settings.dart';

class AboutInfo {
  AboutInfo._();
  static const name = 'Video Player';
  static const author = 'Moun Sokdara';
  static const displayVersion = '1.0.2.1';
  static const legalese = 'Local-only Android player. Material 3.';
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _info;
  int _taps = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((v) {
      if (mounted) setState(() => _info = v);
    });
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (now.difference(_lastTap) > const Duration(seconds: 2)) _taps = 0;
    _lastTap = now;
    _taps += 1;
    if (appSettings.developerEnabled) {
      SlideSnackBar.show(context, message: 'Developer options are on', behavior: SnackBarBehavior.floating);
      return;
    }
    final left = 10 - _taps;
    if (left > 0 && left <= 3) {
      SlideSnackBar.show(context, message: '$left tap${left == 1 ? '' : 's'} away from developer options', behavior: SnackBarBehavior.floating);
    }
    if (_taps >= 10) {
      _taps = 0;
      appSettings.developerEnabled = true;
      unawaited(appSettings.save());
      unawaited(HapticFeedback.mediumImpact());
      setState(() {});
      SlideSnackBar.show(context, message: 'Developer options enabled', behavior: SnackBarBehavior.floating);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final version = _info == null
        ? AboutInfo.displayVersion
        : '${AboutInfo.displayVersion} (${_info!.buildNumber})';
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.play_circle_fill, size: 40),
          ),
          const SizedBox(height: 16),
          Text(AboutInfo.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Created by'),
            subtitle: const Text(AboutInfo.author),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tag),
            title: const Text('Version'),
            subtitle: const Text(AboutInfo.displayVersion),
            onTap: _onVersionTap,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.balance_outlined),
            title: const Text('Open source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AboutInfo.name,
              applicationVersion: version,
              applicationLegalese: '${AboutInfo.legalese}\nCreated by ${AboutInfo.author}.',
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: const Text('Source on GitHub'),
            subtitle: const Text('github.com/mounsokdara/video-player'),
            onTap: () => launchUrl(
              Uri.parse('https://github.com/mounsokdara/video-player'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          if (appSettings.developerEnabled) ...[
            const Divider(height: 32),
            Text('Developer options', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log debug'),
              subtitle: const Text('Enable developer logging'),
              value: appSettings.debugLog,
              onChanged: (v) {
                setState(() => appSettings.debugLog = v);
                unawaited(appSettings.save());
                DeveloperLog.append('debugLog=$v');
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VideoLogOverlay'),
              subtitle: const Text('Show live yellow diagnostic text over the video'),
              value: appSettings.videoLogOverlay,
              onChanged: (v) async {
                setState(() => appSettings.videoLogOverlay = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overlay: playback state'),
              subtitle: const Text('Position, duration, play/pause, buffering, size and FPS'),
              value: appSettings.videoLogShowState,
              onChanged: (v) async {
                setState(() => appSettings.videoLogShowState = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overlay: media info'),
              subtitle: const Text('Pixel format, transfer, primaries, matrix and HDR detection'),
              value: appSettings.videoLogShowMedia,
              onChanged: (v) async {
                setState(() => appSettings.videoLogShowMedia = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overlay: render info'),
              subtitle: const Text('Render mode and active video filter'),
              value: appSettings.videoLogShowRender,
              onChanged: (v) async {
                setState(() => appSettings.videoLogShowRender = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overlay: decoder info'),
              subtitle: const Text('Hardware/software decoder and render capability'),
              value: appSettings.videoLogShowDecoder,
              onChanged: (v) async {
                setState(() => appSettings.videoLogShowDecoder = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overlay: timing / screen'),
              subtitle: const Text('Display resolution, refresh rate and render timing data'),
              value: appSettings.videoLogShowTiming,
              onChanged: (v) async {
                setState(() => appSettings.videoLogShowTiming = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log player events'),
              subtitle: const Text('Open, play, pause, seek, repeat and close events'),
              value: appSettings.logPlayerEvents,
              onChanged: (v) async {
                setState(() => appSettings.logPlayerEvents = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log gesture events'),
              subtitle: const Text('Pinch, seek, brightness, volume and tap gesture events'),
              value: appSettings.logGestureEvents,
              onChanged: (v) async {
                setState(() => appSettings.logGestureEvents = v);
                await appSettings.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log lifecycle events'),
              subtitle: const Text('App/player resume, pause and background transitions'),
              value: appSettings.logLifecycleEvents,
              onChanged: (v) async {
                setState(() => appSettings.logLifecycleEvents = v);
                await appSettings.save();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.terminal),
              title: const Text('Console'),
              subtitle: const Text('Debug log and crash breadcrumbs'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeveloperConsolePage()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DeveloperConsolePage extends StatefulWidget {
  const DeveloperConsolePage({super.key});

  @override
  State<DeveloperConsolePage> createState() => _DeveloperConsolePageState();
}

class _DeveloperConsolePageState extends State<DeveloperConsolePage> {
  String _text() {
    final body = StringBuffer()
      ..writeln('=== debug ===')
      ..writeln(DeveloperLog.text)
      ..writeln()
      ..writeln('=== crash ===')
      ..writeln(CrashLog.text);
    return body.toString();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                SlideSnackBar.show(context, message: 'Copied', behavior: SnackBarBehavior.floating);
              }
            },
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: () async {
              DeveloperLog.clear();
              await CrashLog.clear();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
        ),
      ),
    );
  }
}
