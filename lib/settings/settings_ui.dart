import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/about/about_info.dart';
import 'package:video_player_app/about/about_page.dart';
import 'package:video_player_app/core/crash.dart';
import 'package:video_player_app/player/hud.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/main.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/settings/settings.dart';
import 'package:video_player_app/playback/session.dart';
import 'package:video_player_app/core/material_you.dart';
import 'package:video_player_app/core/widgets.dart';
import 'package:video_player_app/about/about_widgets.dart' show standaloneBack;

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

/// Route name -> index in [_settingsCategories], for the per-category activities.
const _standaloneCategory = {'/general': 0, '/video': 1, '/accessibility': 2, '/theme': 3};

/// Activity route of each entry in [_settingsCategories].
const _categoryRoutes = ['/general', '/video', '/accessibility', '/theme'];

/// Full-screen page for an activity that shows one settings category (or the equalizer) on its own,
/// or null for any other route. Reuses the same widgets as the Settings activity; the back arrow
/// closes the activity.
Widget? standaloneSettingsPage(String route, VoidCallback onChanged) {
  if (route == '/equalizer') return const EqualizerPage();
  final i = _standaloneCategory[route];
  if (i == null) return null;
  return _SettingsBack(onBack: SystemNavigator.pop, child: _settingsCategories[i].build(onChanged));
}

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
  /// Category selected in the sidebar (large screens); the first one while still null.
  int? _picked;

  void _close() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kSettingsSidebarWidth;
    if (!wide) {
      // Tabs sidebar hidden: the list of categories; each one opens as its own activity with the
      // system slide transition (see SettingsHub).
      return Scaffold(body: SettingsHub(onChanged: widget.onChanged, onBack: _close));
    }
    final selected = _picked ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    final cat = _settingsCategories[selected];
    // Round icon colors per category, like the account-style sidebar.
    final iconBg = <Color>[
      scheme.primaryContainer,
      scheme.tertiaryContainer,
      scheme.secondaryContainer,
      scheme.surfaceContainerHighest,
    ];
    final iconFg = <Color>[
      scheme.onPrimaryContainer,
      scheme.onTertiaryContainer,
      scheme.onSecondaryContainer,
      scheme.onSurface,
    ];
    return SystemBarSafeZone(child: Scaffold(
      backgroundColor: scheme.surface,
      body: Padding(
        // Side insets are handled by the SystemBarSafeZone around this Scaffold.
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            // Sidebar tabs: only built on large screens. Phones never see it.
            SizedBox(
              width: 320,
              child: ListView(
                padding: EdgeInsets.fromLTRB(12, pad.top + 8, 12, pad.bottom + 16),
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: _close,
                      ),
                      const SizedBox(width: 4),
                      Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _settingsCategories.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Material(
                        color: i == selected ? scheme.primaryContainer : Colors.transparent,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => setState(() => _picked = i),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: i == selected ? scheme.surface : iconBg[i % iconBg.length],
                                  foregroundColor: i == selected ? scheme.primary : iconFg[i % iconFg.length],
                                  child: Icon(_settingsCategories[i].icon),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    _settingsCategories[i].title,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          color: i == selected ? scheme.onPrimaryContainer : scheme.onSurface,
                                          fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('pane$selected'),
                child: cat.build(widget.onChanged),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

/// Lets a category page (shown full screen on a phone) draw a back arrow that
/// returns to the main settings list. Absent in the large-screen detail pane.
class _SettingsBack extends InheritedWidget {
  const _SettingsBack({required this.onBack, required super.child});
  final VoidCallback onBack;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsBack>()?.onBack;

  @override
  bool updateShouldNotify(_SettingsBack oldWidget) => true;
}

Widget? settingsBackLeading(BuildContext context) {
  final back = _SettingsBack.of(context);
  return back == null ? null : BackButton(onPressed: back);
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
    return SystemBarSafeZone(child: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          leading: onBack == null ? null : BackButton(onPressed: onBack),
          title: const Text('Settings'),
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: pad.bottom + 24),
          sliver: SliverList.list(children: [
            for (var i = 0; i < _settingsCategories.length; i++)
              _categoryTile(context, scheme, i),
          ]),
        ),
      ],
    ));
  }

  Widget _categoryTile(BuildContext context, ColorScheme scheme, int i) {
    final c = _settingsCategories[i];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        child: Icon(c.icon),
      ),
      title: Text(c.title),
      subtitle: Text(c.sub),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await openPage(context, _categoryRoutes[i], () => c.build(onChanged));
        onChanged();
      },
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await openPage(context, '/settings', () => Scaffold(body: SettingsHub(onChanged: onChanged)));
                onChanged();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.equalizer),
              title: const Text('Equalizer'),
              subtitle: Text(appSettings.eqEnabled ? 'On · ${appSettings.eqPreset}' : 'Off'),
              onTap: () => openPage(context, '/equalizer', () => const EqualizerPage()),
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
                await openPage(context, '/about', () => const AboutPage());
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

    return SystemBarSafeZone(child: Scaffold(
      appBar: AppBar(leading: settingsBackLeading(context), title: const Text('General')),
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
    ));
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

    return SystemBarSafeZone(child: Scaffold(
      appBar: AppBar(leading: settingsBackLeading(context), title: const Text('Video')),
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
    ));
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

    return SystemBarSafeZone(child: Scaffold(
      appBar: AppBar(leading: settingsBackLeading(context), title: const Text('Accessibility')),
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
    ));
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

    return SystemBarSafeZone(child: Scaffold(
      appBar: AppBar(leading: settingsBackLeading(context), title: const Text('Theme')),
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
    ));
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

  /// Width from which the equalizer switches to the two-pane large-screen layout.
  static const double _wideWidth = 720;

  String _hzLabel(int i) {
    final hz = AppSettings.eqBandHz[i];
    return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '$hz';
  }

  String _dbLabel(double db) {
    final n = db.round();
    return n > 0 ? '+$n' : '$n';
  }

  Widget _presetChips({required bool wrap}) {
    final s = appSettings;
    final chips = <Widget>[
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
    ];
    if (wrap) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return ChipScroller(children: chips);
  }

  /// The ten band sliders. [height] is the slider track height; with [scale] a dB ruler is drawn on
  /// the left (large screens).
  Widget _bands(double height, {required bool scale}) {
    final s = appSettings;
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 10, color: cs.onSurfaceVariant);
    final ruler = SizedBox(
      width: 30,
      child: Column(
        children: [
          Text(' ', style: small),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+${maxDb.round()}', style: small),
                Text('0', style: small),
                Text('${minDb.round()}', style: small),
              ],
            ),
          ),
          Text(' ', style: small),
        ],
      ),
    );
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scale) ruler,
          for (var i = 0; i < 10; i++)
            Expanded(
              child: Column(
                children: [
                  Text(_dbLabel(_bandDb(i)), style: small),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: Slider(
                        min: minDb,
                        max: maxDb,
                        value: _bandDb(i),
                        onChanged: s.eqEnabled
                            ? (v) {
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
                  Text(_hzLabel(i), style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _effects() {
    final s = appSettings;
    return [
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
        onChanged: s.bassBoostOn ? (v) => setState(() => s.bassBoost = v.round()) : null,
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
        onChanged: s.surroundOn ? (v) => setState(() => s.surround = v.round()) : null,
        onChangeEnd: (_) => _persist(),
      ),
    ];
  }

  Widget _card(Widget child) {
    final cs = Theme.of(context).colorScheme;
    // Material so the switch rows inside paint their ripple on the card.
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  Widget _heading(String text) =>
      Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final pad = MediaQuery.viewPaddingOf(context);
    final bottom = pad.bottom + MediaQuery.viewInsetsOf(context).bottom;
    return SystemBarSafeZone(child: Scaffold(
      appBar: AppBar(
        leading: standaloneBack(context),
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
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _wideWidth;
          if (!wide) {
            // Phones: one column, capped width so a tall tablet in portrait does not stretch it.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottom),
                  children: [
                    _heading('Presets'),
                    const SizedBox(height: 8),
                    _presetChips(wrap: false),
                    const SizedBox(height: 20),
                    _bands(220, scale: false),
                    const SizedBox(height: 12),
                    ..._effects(),
                  ],
                ),
              ),
            );
          }
          // Large screens: bands on the left (as tall as the screen allows), presets and effects
          // in a side column, everything centred with a maximum width.
          final bandHeight = (box.maxHeight - 130 - bottom).clamp(260.0, 480.0).toDouble();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 32 + bottom),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _card(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heading('Bands (dB)'),
                          const SizedBox(height: 12),
                          _bands(bandHeight, scale: true),
                        ],
                      )),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 340,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _card(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _heading('Presets'),
                              const SizedBox(height: 10),
                              _presetChips(wrap: true),
                            ],
                          )),
                          const SizedBox(height: 16),
                          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _heading('Effects'),
                            ..._effects(),
                          ])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ));
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
