import 'package:flutter/material.dart';

import 'package:video_player_app/about/about_widgets.dart';
import 'package:video_player_app/about/console_page.dart';
import 'package:video_player_app/core/developer_log.dart';
import 'package:video_player_app/core/widgets.dart';
import 'package:video_player_app/settings/settings.dart';

class _DevOption {
  const _DevOption(this.title, this.subtitle, this.get, this.set);
  final String title;
  final String subtitle;
  final bool Function(AppSettings s) get;
  final void Function(AppSettings s, bool v) set;
}

final _options = <_DevOption>[
  _DevOption('Log debug', 'Enable developer logging', (s) => s.debugLog, (s, v) => s.debugLog = v),
  _DevOption('VideoLogOverlay', 'Show live yellow diagnostic text over the video', (s) => s.videoLogOverlay, (s, v) => s.videoLogOverlay = v),
  _DevOption('Overlay: playback state', 'Position, duration, play/pause, buffering, size and FPS', (s) => s.videoLogShowState, (s, v) => s.videoLogShowState = v),
  _DevOption('Overlay: media info', 'Pixel format, transfer, primaries, matrix and HDR detection', (s) => s.videoLogShowMedia, (s, v) => s.videoLogShowMedia = v),
  _DevOption('Overlay: render info', 'Render mode and active video filter', (s) => s.videoLogShowRender, (s, v) => s.videoLogShowRender = v),
  _DevOption('Overlay: decoder info', 'Hardware/software decoder and render capability', (s) => s.videoLogShowDecoder, (s, v) => s.videoLogShowDecoder = v),
  _DevOption('Overlay: timing / screen', 'Display resolution, refresh rate and render timing data', (s) => s.videoLogShowTiming, (s, v) => s.videoLogShowTiming = v),
  _DevOption('Log player events', 'Open, play, pause, seek, repeat and close events', (s) => s.logPlayerEvents, (s, v) => s.logPlayerEvents = v),
  _DevOption('Log gesture events', 'Pinch, seek, brightness, volume and tap gesture events', (s) => s.logGestureEvents, (s, v) => s.logGestureEvents = v),
  _DevOption('Log lifecycle events', 'App/player resume, pause and background transitions', (s) => s.logLifecycleEvents, (s, v) => s.logLifecycleEvents = v),
];

/// Shown on the About page only after developer options are unlocked.
class DeveloperOptionsSection extends StatefulWidget {
  const DeveloperOptionsSection({super.key});

  @override
  State<DeveloperOptionsSection> createState() => _DeveloperOptionsSectionState();
}

class _DeveloperOptionsSectionState extends State<DeveloperOptionsSection> {
  void _toggle(_DevOption o, bool v) {
    setState(() => o.set(appSettings, v));
    appSettings.save();
    if (identical(o, _options.first)) DeveloperLog.append('debugLog=$v');
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AboutSection(
        icon: Icons.code,
        title: 'Developer options',
        subtitle: 'Debug logging and on-video diagnostics',
        child: Column(children: [
          for (final o in _options)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(o.title),
              subtitle: Text(o.subtitle, style: const TextStyle(fontSize: 12)),
              value: o.get(appSettings),
              onChanged: (v) => _toggle(o, v),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      AboutGroup(items: [
        AboutItem(
          icon: Icons.terminal,
          title: 'Console',
          subtitle: 'Debug log and crash breadcrumbs',
          onTap: () => openPage(context, '/console', () => const ConsolePage()),
        ),
      ]),
    ]);
  }
}
