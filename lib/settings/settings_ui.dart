import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/settings/about.dart';
import 'package:video_player_app/core/crash.dart';
import 'package:video_player_app/player/hud.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/main.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/settings/settings.dart';
import 'package:video_player_app/playback/session.dart';
import 'package:video_player_app/core/material_you.dart';
import 'package:video_player_app/core/widgets.dart';

/// One entry in the settings sidebar / category list.
class _SettingsCategory {
  const _SettingsCategory(this.icon, this.title, this.sub, this.build);
  final IconData icon;
  final String title;
  final String sub;
  final Widget Function(VoidCallback onChanged) build;
}

final _settingsCategories = <_SettingsCategory>[
  _SettingsCategory(Icons.tune, 'General', 'Library, scanning, tabs, storage', (c) => GeneralSettings(onChanged: c)),
  _SettingsCategory(Icons.videocam_outlined, 'Video', 'Display, playback, decoder, gestures', (c) => VideoSettings(onChanged: c)),
  _SettingsCategory(Icons.accessibility_new, 'Accessibility', 'Color filters, motion, text', (c) => AccessSettings(onChanged: c)),
  _SettingsCategory(Icons.palette_outlined, 'Theme', 'Dark / light / system and seed color', (c) => ThemeSettings(onChanged: c)),
];

/// Width from which the Settings screen shows its tabs sidebar.
const double kSettingsSidebarWidth = 840;

/// Root of the Settings activity (`/settings`).
/// Phones: category list. Large screens: tabs sidebar on the left, the
/// selected category on the right.
class SettingsHost extends StatefulWidget {
  const SettingsHost({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<SettingsHost> createState() => _SettingsHostState();
}

class _SettingsHostState extends State<SettingsHost> {
  int _selected = 0;

  void _close() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kSettingsSidebarWidth;
    if (!wide) {
      return Scaffold(
        body: SettingsHub(onChanged: widget.onChanged, onBack: _close),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    final cat = _settingsCategories[_selected];
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(left: pad.left, right: pad.right),
        child: Row(
          children: [
            SizedBox(
              width: 300,
              child: Material(
                color: scheme.surfaceContainerLow,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(12, pad.top + 8, 12, pad.bottom + 16),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Back',
                          onPressed: _close,
                        ),
                        const SizedBox(width: 4),
                        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _settingsCategories.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          selected: i == _selected,
                          selectedTileColor: scheme.secondaryContainer,
                          selectedColor: scheme.onSecondaryContainer,
                          shape: const StadiumBorder(),
                          leading: Icon(_settingsCategories[i].icon),
                          title: Text(_settingsCategories[i].title),
                          onTap: () => setState(() => _selected = i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(_selected),
                child: cat.build(widget.onChanged),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category list shown on phones inside the Settings activity.
class SettingsHub extends StatelessWidget {
  const SettingsHub({super.key, required this.onChanged, this.onBack});
  final VoidCallback onChanged;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          leading: onBack == null ? null : BackButton(onPressed: onBack),
          title: const Text('Settings'),
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: pad.bottom + 24),
          sliver: SliverList.list(children: [
            for (final c in _settingsCategories)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundColor: scheme.onSurface,
                  child: Icon(c.icon),
                ),
                title: Text(c.title),
                subtitle: Text(c.sub),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => c.build(onChanged)));
                  onChanged();
                },
              ),
          ]),
        ),
      ],
    );
  }
}

/// The "More" tab: opens the Settings activity, plus equalizer, crash report, about.
class MoreHub extends StatelessWidget {
  const MoreHub({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    return CustomScrollView(
      slivers: [
        const SliverAppBar(pinned: true, title: Text('More')),
        SliverPadding(
          padding: EdgeInsets.only(bottom: pad.bottom + 24),
          sliver: SliverList.list(children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.surfaceContainerHighest,
                foregroundColor: scheme.onSurface,
                child: const Icon(Icons.settings_outlined),
              ),
              title: const Text('Settings'),
              subtitle: const Text('General, video, accessibility, theme'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                final ok = await AndroidBridge.openSettings();
                if (!ok && context.mounted) {
                  // Native screen unavailable: fall back to the in-app list.
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => Scaffold(body: SettingsHub(onChanged: onChanged))),
                  );
                  onChanged();
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.equalizer),
              title: const Text('Equalizer'),
              subtitle: Text(appSettings.eqEnabled ? 'On · ${appSettings.eqPreset}' : 'Off'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerPage())),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Crash report'),
              subtitle: const Text('Copy the last error log'),
              onTap: () => CrashLog.show(),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: Text('Video Player ${AboutInfo.displayVersion}'),
              onTap: () async {
                if (!context.mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()));
                onChanged();
              },
            ),
          ]),
        ),
      ],
    );
  }
}

Future<void> showTabVisibilityDialog(BuildContext context, VoidCallback onChanged) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: StatefulBuilder(builder: (ctx, ss) {
          final s = appSettings;
          Widget row(String id) {
            final visible = !s.hiddenTabs.contains(id);
            final last = s.visibleTabs.length == 1 && visible;
            return SwitchListTile(
              title: Text(AppSettings.tabLabels[id] ?? id),
              subtitle: Text(last ? 'Keep at least one tab' : visible ? 'Shown in the bar' : 'Moved to the 3-dot menu'),
              value: visible,
              onChanged: last && visible
                  ? null
                  : (v) {
                      ss(() => s.hideTab(id, !v));
                      s.save();
                      onChanged();
                    },
            );
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Visible tabs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  subtitle: Text('Hidden tabs move to the top-right menu. Keep at least one.'),
                ),
                row('videos'),
                row('folders'),
                row('settings'),
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
      );
    },
  );
}

class GeneralSettings extends StatefulWidget {
  const GeneralSettings({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<GeneralSettings> createState() => _GeneralSettingsState();
}

class _GeneralSettingsState extends State<GeneralSettings> {
  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final insets = MediaQuery.viewInsetsOf(context);
    final pad = MediaQuery.viewPaddingOf(context);
    void set(VoidCallback fn) {
      setState(fn);
      s.save();
      widget.onChanged();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('General')),
      body: ListView(
        padding: EdgeInsets.only(bottom: insets.bottom + pad.bottom + 24),
        children: [
          SwitchListTile(title: const Text('Scan library on start'), value: s.scanOnStart, onChanged: (v) => set(() => s.scanOnStart = v)),
          SwitchListTile(
            title: const Text('Auto refresh'),
            subtitle: const Text('Refresh when videos are added, changed, or deleted'),
            value: s.autoRefresh,
            onChanged: (v) => set(() => s.autoRefresh = v),
          ),
          SwitchListTile(title: const Text('Confirm before delete'), value: s.confirmDelete, onChanged: (v) => set(() => s.confirmDelete = v)),
          SwitchListTile(
            title: const Text('Show hidden files'),
            subtitle: const Text('Include dot-folders and hidden videos when scanning'),
            value: s.showHiddenFolders,
            onChanged: (v) {
              set(() => s.showHiddenFolders = v);
              unawaited(() async {
                await library.applyHidden(v);
                widget.onChanged();
              }());
            },
          ),
          SwitchListTile(
            title: const Text('Skip .nomedia folder'),
            subtitle: const Text('Ignore folders that contain a .nomedia file'),
            value: s.skipNomedia,
            onChanged: (v) {
              set(() => s.skipNomedia = v);
              unawaited(() async {
                while (library.scanning) {
                  await Future<void>.delayed(const Duration(milliseconds: 40));
                }
                await library.scan();
                widget.onChanged();
              }());
            },
          ),
          ListTile(
            title: const Text('Visible tabs'),
            subtitle: Text('Showing ${s.visibleTabs.map((t) => AppSettings.tabLabels[t]).join(', ')}'),
            trailing: const Icon(Icons.tune),
            onTap: () => showTabVisibilityDialog(context, () {
              set(() {});
            }),
          ),
          ListTile(
            title: const Text('Quick actions'),
            trailing: const Icon(Icons.tune),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuickActionsEditor(onChanged: widget.onChanged))),
          ),
          ListTile(
            title: const Text('Title bar buttons'),
            trailing: const Icon(Icons.tune),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TitleBarEditor(onChanged: widget.onChanged))),
          ),
          ListTile(
            title: const Text('Floating action buttons'),
            trailing: const Icon(Icons.tune),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HudEditorPage(onChanged: widget.onChanged))),
          ),
          SwitchListTile(title: const Text('Remember playback progress'), value: s.rememberPlayback, onChanged: (v) => set(() => s.rememberPlayback = v)),
          ListTile(
            title: const Text('Clear resume history'),
            onTap: () => set(() => s.resumeMap.clear()),
          ),
          ListTile(
            title: const Text('App permissions'),
            subtitle: const Text('Open system settings for this app'),
            onTap: openAppSettings,
          ),
        ],
      ),
    );
  }
}

class VideoSettings extends StatefulWidget {
  const VideoSettings({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<VideoSettings> createState() => _VideoSettingsState();
}

class _VideoSettingsState extends State<VideoSettings> {
  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final insets = MediaQuery.viewInsetsOf(context);
    final pad = MediaQuery.viewPaddingOf(context);
    void set(VoidCallback fn) {
      setState(fn);
      s.save();
      widget.onChanged();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: ListView(
        padding: EdgeInsets.only(bottom: insets.bottom + pad.bottom + 24),
        children: [
          _h('Display'),
          SwitchListTile(title: const Text('Remaining time'), subtitle: const Text('Show countdown instead of duration'), value: s.showRemaining, onChanged: (v) => set(() => s.showRemaining = v)),
          SwitchListTile(title: const Text('Clock'), subtitle: const Text('Show clock during playback'), value: s.showClock, onChanged: (v) => set(() => s.showClock = v)),
          SwitchListTile(title: const Text('Battery'), value: s.showBattery, onChanged: (v) => set(() => s.showBattery = v)),
          _h('Screen orientation'),
          ListTile(
            title: const Text('Default rotation'),
            subtitle: Text(s.rotation.label),
            onTap: () async {
              final modes = <RotationLock>[
                RotationLock.none,
                RotationLock.auto,
                RotationLock.autoVideo,
                RotationLock.landscape,
                RotationLock.portrait,
                RotationLock.landscapeNormal,
                RotationLock.landscapeReverse,
                RotationLock.portraitNormal,
                RotationLock.portraitReverse,
              ];
              final v = await showAppSheet<RotationLock>(
                context: context,
                initial: 0.62,
                children: (ctx) => [
                  for (final e in modes)
                    ListTile(title: Text(e.label), onTap: () => Navigator.pop(ctx, e)),
                ],
              );
              if (v != null) set(() => s.rotation = v);
            },
          ),
          _h('Playback'),
          SwitchListTile(title: const Text('Use HW decoder in priority'), value: s.hwPriority, onChanged: (v) => set(() { s.hwPriority = v; s.decoder = v ? DecoderMode.hw : DecoderMode.sw; })),
          ListTile(
            title: const Text('Decoder'),
            subtitle: Text(s.decoder.name.toUpperCase()),
            onTap: () async {
              final v = await showModalBottomSheet<DecoderMode>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final e in DecoderMode.values) ListTile(title: Text(e.name.toUpperCase()), onTap: () => Navigator.pop(ctx, e)),
                  ]),
                ),
              );
              if (v != null) set(() => s.decoder = v);
            },
          ),
          ListTile(
            title: const Text('Time to fast forward and rewind'),
            subtitle: Text('${s.seekStepSeconds} seconds'),
            trailing: SizedBox(
              width: 140,
              child: Slider(
                min: 5,
                max: 30,
                divisions: 5,
                value: s.seekStepSeconds.toDouble(),
                onChanged: (v) => set(() => s.seekStepSeconds = v.round()),
              ),
            ),
          ),
          SwitchListTile(title: const Text('PIP'), value: s.autoMiniplayer, onChanged: (v) => set(() => s.autoMiniplayer = v)),
          SwitchListTile(
            title: const Text('Mini player'),
            value: s.inAppMiniplayer,
            onChanged: (v) => set(() => s.inAppMiniplayer = v),
          ),
          SwitchListTile(
            title: const Text('Always hide navigation bar'),
            subtitle: const Text('Keep system bars hidden even when player controls are visible. Otherwise bars follow the controller.'),
            value: s.alwaysHideNavBar,
            onChanged: (v) => set(() => s.alwaysHideNavBar = v),
          ),
          SwitchListTile(
            title: const Text('Background play'),
            subtitle: const Text('Keeps audio going with a music-style notification when you leave the app'),
            value: s.backgroundPlay,
            onChanged: (v) {
              set(() => s.backgroundPlay = v);
              unawaited(() async {
                if (v) {
                  try {
                    await Permission.notification.request();
                  } catch (_) {}
                }
                await PlaybackSession.syncNotification();
              }());
            },
          ),
          SwitchListTile(title: const Text('Remember background play'), subtitle: const Text('Keep the option on for every video'), value: s.rememberBackgroundPlay, onChanged: (v) => set(() => s.rememberBackgroundPlay = v)),
          SwitchListTile(title: const Text('Remember aspect ratio'), value: s.rememberAspect, onChanged: (v) => set(() => s.rememberAspect = v)),
          SwitchListTile(title: const Text('Resume'), subtitle: const Text('Continue from where you stopped'), value: s.resumePlayback, onChanged: (v) => set(() => s.resumePlayback = v)),
          SwitchListTile(title: const Text('Remember speed'), value: s.rememberSpeed, onChanged: (v) => set(() => s.rememberSpeed = v)),
          SwitchListTile(
            title: const Text('Pitch shift'),
            subtitle: const Text('When on, pitch follows speed. When off, speed changes without chipmunk audio.'),
            value: s.pitchShift,
            onChanged: (v) {
              set(() => s.pitchShift = v);
              final c = PlaybackSession.controller;
              if (c != null) {
                unawaited(c.applyTempo(rate: PlaybackSession.speed, pitchShift: v));
              }
            },
          ),
          SwitchListTile(title: const Text('Remember brightness'), subtitle: const Text('Off follows system brightness'), value: s.rememberBrightness, onChanged: (v) => set(() => s.rememberBrightness = v)),
          SwitchListTile(title: const Text('Long press to play at 2×'), value: s.longPress2x, onChanged: (v) => set(() => s.longPress2x = v)),
          SwitchListTile(title: const Text('Long press vibration'), value: s.longPressVibration, onChanged: (v) => set(() => s.longPressVibration = v)),
          SwitchListTile(title: const Text('Double tap to fast forward and rewind'), value: s.doubleTapSeek, onChanged: (v) => set(() => s.doubleTapSeek = v)),
          SwitchListTile(title: const Text('Auto play next'), subtitle: const Text('Takes effect in Order mode'), value: s.autoPlayNext, onChanged: (v) => set(() => s.autoPlayNext = v)),
          SwitchListTile(title: const Text('Gesture control'), value: s.gestureControl, onChanged: (v) => set(() => s.gestureControl = v)),
          SwitchListTile(
            title: const Text('Allow zoom inside video'),
            subtitle: const Text('Pinch to zoom the picture.'),
            value: s.allowZoom,
            onChanged: (v) => set(() => s.allowZoom = v),
          ),
          SwitchListTile(title: const Text('Remember HDR mode'), value: s.rememberHdr, onChanged: (v) => set(() => s.rememberHdr = v)),
        ],
      ),
    );
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );
}

class AccessSettings extends StatefulWidget {
  const AccessSettings({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<AccessSettings> createState() => _AccessSettingsState();
}

class _AccessSettingsState extends State<AccessSettings> {
  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final insets = MediaQuery.viewInsetsOf(context);
    final pad = MediaQuery.viewPaddingOf(context);
    void set(VoidCallback fn) {
      setState(fn);
      s.save();
      widget.onChanged();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        padding: EdgeInsets.only(bottom: insets.bottom + pad.bottom + 24),
        children: [
          _h('Display filters'),
          SwitchListTile(title: const Text('High contrast'), value: s.highContrast, onChanged: (v) => set(() => s.highContrast = v)),
          SwitchListTile(title: const Text('Grayscale'), value: s.grayscale, onChanged: (v) => set(() => s.grayscale = v)),
          SwitchListTile(title: const Text('Invert colors'), value: s.invertColors, onChanged: (v) => set(() => s.invertColors = v)),
          SwitchListTile(title: const Text('Night mode'), value: s.nightMode, onChanged: (v) => set(() => s.nightMode = v)),
          SwitchListTile(title: const Text('Extra dim'), value: s.extraDim, onChanged: (v) => set(() => s.extraDim = v)),
          SwitchListTile(
            title: const Text('Color correction'),
            subtitle: const Text('Apply contrast, saturation, gamma, and hue'),
            value: s.colorCorrection,
            onChanged: (v) => set(() => s.colorCorrection = v),
          ),
          SwitchListTile(title: const Text('Deuteranopia filter'), value: s.colorBlindDeuteranopia, onChanged: (v) => set(() => s.colorBlindDeuteranopia = v)),
          SwitchListTile(title: const Text('Protanopia filter'), value: s.colorBlindProtanopia, onChanged: (v) => set(() => s.colorBlindProtanopia = v)),
          SwitchListTile(title: const Text('Tritanopia filter'), value: s.colorBlindTritanopia, onChanged: (v) => set(() => s.colorBlindTritanopia = v)),
          _h('Motion and control'),
          SwitchListTile(title: const Text('Reduce motion'), value: s.reduceMotion, onChanged: (v) => set(() => s.reduceMotion = v)),
          SwitchListTile(title: const Text('Large controls'), value: s.largeControls, onChanged: (v) => set(() => s.largeControls = v)),
          SwitchListTile(title: const Text('Bold text'), value: s.boldText, onChanged: (v) => set(() => s.boldText = v)),
          ListTile(
            title: const Text('Interface scale'),
            subtitle: Slider(min: 0.85, max: 1.35, value: s.uiScale, onChanged: (v) => set(() => s.uiScale = v)),
          ),
        ],
      ),
    );
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );
}

class ThemeSettings extends StatefulWidget {
  const ThemeSettings({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<ThemeSettings> createState() => _ThemeSettingsState();
}

class _ThemeSettingsState extends State<ThemeSettings> {
  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final pad = MediaQuery.viewPaddingOf(context);
    void set(VoidCallback fn) {
      setState(fn);
      s.save();
      widget.onChanged();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + pad.bottom),
        children: [
          const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // Theme button, same control as Khmer Calendar: text-only, full width, check mark on wide screens.
          LayoutBuilder(
            builder: (ctx, box) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: box.maxWidth),
                child: SegmentedButton<ThemeModePref>(
                  showSelectedIcon: box.maxWidth > 380,
                  segments: const [
                    ButtonSegment(value: ThemeModePref.light, label: Text('Light')),
                    ButtonSegment(value: ThemeModePref.dark, label: Text('Dark')),
                    ButtonSegment(value: ThemeModePref.system, label: Text('System')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => set(() => s.themeMode = v.first),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dynamic color'),
            subtitle: const Text('Use wallpaper colors when the device supports Material You'),
            value: s.dynamicColor,
            onChanged: (v) => set(() => s.dynamicColor = v),
          ),
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: s.dynamicColor,
            child: Opacity(
              opacity: s.dynamicColor ? 0.38 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Material You color', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  // Same colour plates as Khmer Calendar.
                  MaterialYouChips(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    selected: Color(s.seedColor),
                    onPick: (c) => set(() {
                      s.seedColor = c.circle.toARGB32();
                      s.dynamicColor = false;
                    }),
                  ),
                  Builder(builder: (context) {
                    final cs = Theme.of(context).colorScheme;
                    final rgb = s.seedColor & 0xFFFFFF;
                    final isCustom = !s.dynamicColor &&
                        !schemeChips.any((c) => (c.circle.toARGB32() & 0xFFFFFF) == rgb);
                    return ListTile(
                    contentPadding: isCustom ? const EdgeInsets.symmetric(horizontal: 12) : EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: isCustom ? BorderSide(color: cs.primary, width: 2) : BorderSide.none,
                    ),
                    selected: isCustom,
                    selectedTileColor: cs.primaryContainer.withValues(alpha: 0.5),
                    enabled: !s.dynamicColor,
                    leading: CircleAvatar(backgroundColor: Color(s.seedColor)),
                    title: const Text('Custom color'),
                    subtitle: Text('#${s.seedColor.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'),
                    trailing: Icon(isCustom ? Icons.check_circle : Icons.chevron_right),
                    onTap: s.dynamicColor
                        ? null
                        : () async {
                            final picked = await showColorPicker(context, Color(s.seedColor));
                            if (picked != null) {
                              set(() {
                                s.seedColor = picked.toARGB32();
                                s.dynamicColor = false;
                              });
                            }
                          },
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Player style', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          RadioListTile<PlaylistUiStyle>(
            contentPadding: EdgeInsets.zero,
            value: PlaylistUiStyle.sheet,
            groupValue: s.playlistStyle,
            title: const Text('Bottom dialog sheet'),
            subtitle: const Text('Fullscreen player, playlist as a Material sheet'),
            onChanged: (v) {
              if (v != null) set(() => s.playlistStyle = v);
            },
          ),
          RadioListTile<PlaylistUiStyle>(
            contentPadding: EdgeInsets.zero,
            value: PlaylistUiStyle.youtube,
            groupValue: s.playlistStyle,
            title: const Text('YouTube'),
            subtitle: const Text('Watch page: video, details below, list on the right in landscape. Maximize is fullscreen'),
            onChanged: (v) {
              if (v != null) set(() => s.playlistStyle = v);
            },
          ),
        ],
      ),
    );
  }
}

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});
  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  static const minDb = -15.0;
  static const maxDb = 15.0;

  @override
  void initState() {
    super.initState();
    _push();
  }

  Future<void> _push() async {
    try {
      await appSettings.save();
      await AndroidBridge.applyEqualizer(
        enabled: appSettings.eqEnabled,
        bands: appSettings.eqBands,
        bassOn: appSettings.bassBoostOn,
        bass: appSettings.bassBoost,
        surroundOn: appSettings.surroundOn,
        surround: appSettings.surround,
      );
    } catch (e, s) {
      CrashLog.record('EQ', '$e', s);
    }
  }

  Future<void> _persist() async {
    try {
      await appSettings.save();
      await _push();
      if (mounted) setState(() {});
    } catch (e, s) {
      CrashLog.record('EQ', '$e', s);
    }
  }

  double _bandDb(int i) {
    if (i < 0 || i >= appSettings.eqBands.length) return 0;
    return (appSettings.eqBands[i] / 100).clamp(minDb, maxDb).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final pad = MediaQuery.viewPaddingOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          Switch(
            value: s.eqEnabled,
            onChanged: (v) async {
              s.eqEnabled = v;
              await _persist();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + pad.bottom + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          Text('Presets', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ChipScroller(
            children: [
              for (final name in AppSettings.eqPresets.keys)
                ChoiceChip(
                  label: Text(name),
                  selected: s.eqPreset == name,
                  onSelected: (_) async {
                    s.applyPreset(name);
                    s.eqEnabled = true;
                    await _persist();
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 10; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: -1,
                            child: Slider(
                              min: minDb,
                              max: maxDb,
                              value: _bandDb(i),
                              onChanged: s.eqEnabled
                                  ? (v) async {
                                      setState(() {
                                        s.eqBands[i] = (v * 100).round();
                                        s.eqPreset = 'Custom';
                                      });
                                    }
                                  : null,
                              onChangeEnd: (_) => _persist(),
                            ),
                          ),
                        ),
                        Text(
                          AppSettings.eqBandHz[i] >= 1000
                              ? '${(AppSettings.eqBandHz[i] / 1000).toStringAsFixed(AppSettings.eqBandHz[i] % 1000 == 0 ? 0 : 1)}k'
                              : '${AppSettings.eqBandHz[i]}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bass boost'),
            value: s.bassBoostOn,
            onChanged: (v) async {
              s.bassBoostOn = v;
              if (v) s.eqEnabled = true;
              await _persist();
            },
          ),
          Slider(
            min: 0,
            max: 1000,
            value: s.bassBoost.toDouble(),
            label: '${(s.bassBoost / 10).round()}%',
            onChanged: s.bassBoostOn
                ? (v) async {
                    setState(() => s.bassBoost = v.round());
                  }
                : null,
            onChangeEnd: (_) => _persist(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Surround sound'),
            value: s.surroundOn,
            onChanged: (v) async {
              s.surroundOn = v;
              if (v) s.eqEnabled = true;
              await _persist();
            },
          ),
          Slider(
            min: 0,
            max: 1000,
            value: s.surround.toDouble(),
            label: '${(s.surround / 10).round()}%',
            onChanged: s.surroundOn
                ? (v) async {
                    setState(() => s.surround = v.round());
                  }
                : null,
            onChangeEnd: (_) => _persist(),
          ),
        ],
      ),
    );
  }
}

class QuickActionsEditor extends StatefulWidget {
  const QuickActionsEditor({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<QuickActionsEditor> createState() => _QuickActionsEditorState();
}

class _QuickActionsEditorState extends State<QuickActionsEditor> {
  late List<String> order;
  late Set<String> enabled;

  @override
  void initState() {
    super.initState();
    enabled = appSettings.quickActions.toSet();
    order = [...appSettings.quickActions];
    for (final id in AppSettings.allQuickActions.keys) {
      if (!order.contains(id)) order.add(id);
    }
  }

  Future<void> _persist() async {
    var next = order.where(enabled.contains).toList();
    if (next.isEmpty) next = List<String>.from(AppSettings.defaultQuickActions);
    appSettings.quickActions = next;
    await appSettings.save();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Quick actions')),
      body: ReorderableListView.builder(
        padding: EdgeInsets.only(left: pad.left, right: pad.right, bottom: pad.bottom + 24),
        itemCount: order.length,
        onReorder: (oldIndex, newIndex) async {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = order.removeAt(oldIndex);
            order.insert(newIndex, item);
          });
          await _persist();
        },
        itemBuilder: (ctx, i) {
          final id = order[i];
          return CheckboxListTile(
            key: ValueKey(id),
            value: enabled.contains(id),
            title: Text(AppSettings.allQuickActions[id] ?? id),
            secondary: const Icon(Icons.drag_handle),
            onChanged: (v) async {
              setState(() {
                if (v == true) {
                  enabled.add(id);
                } else {
                  enabled.remove(id);
                }
              });
              await _persist();
            },
          );
        },
      ),
    );
  }
}

Future<Color?> showColorPicker(BuildContext context, Color initial) {
  return SystemBars.modal(
    () => showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final pad = SystemBars.rawOf(context);
        final insets = MediaQuery.viewInsetsOf(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom + pad.bottom),
          child: _ColorPickerSheet(initial: initial),
        );
      },
    ),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor hsv;
  late final TextEditingController hex;

  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(widget.initial.withValues(alpha: 1));
    hex = TextEditingController(text: _hexOf(hsv.toColor()));
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  String _hexOf(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  void _set(HSVColor next, {bool syncHex = true}) {
    setState(() => hsv = next);
    if (syncHex) {
      hex.value = TextEditingValue(
        text: _hexOf(next.toColor()),
        selection: const TextSelection.collapsed(offset: 6),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = hsv.toColor();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Custom color', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: hex,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      prefixText: '#',
                      counterText: '',
                      labelText: 'Hex',
                    ),
                    onChanged: (v) {
                      final raw = v.replaceAll('#', '').trim();
                      if (raw.length != 6) return;
                      final n = int.tryParse(raw, radix: 16);
                      if (n == null) return;
                      _set(HSVColor.fromColor(Color(0xFF000000 | n)), syncHex: false);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _labeled('Hue', hsv.hue, 0, 360, (v) => _set(hsv.withHue(v))),
            _labeled('Saturation', hsv.saturation, 0, 1, (v) => _set(hsv.withSaturation(v))),
            _labeled('Brightness', hsv.value, 0, 1, (v) => _set(hsv.withValue(v))),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Apply')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeled(String label, double value, double min, double max, ValueChanged<double> on) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Slider(min: min, max: max, value: value.clamp(min, max).toDouble(), onChanged: on),
      ],
    );
  }
}
