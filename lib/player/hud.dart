import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_app/about/about_widgets.dart' show standaloneBack;

import 'package:video_player_app/settings/settings.dart';

class HudFab {
  HudFab({required this.id, required this.x, required this.y, this.size = 56});
  String id;
  double x;
  double y;
  double size;

  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y, 'size': size};

  factory HudFab.fromJson(Map<String, dynamic> j) => HudFab(
        id: '${j['id'] ?? 'eq'}',
        x: (j['x'] as num?)?.toDouble() ?? 0.82,
        y: (j['y'] as num?)?.toDouble() ?? 0.78,
        size: (j['size'] as num?)?.toDouble() ?? 56,
      );
}

class HudLayer extends StatelessWidget {
  const HudLayer({super.key, required this.fabs, required this.onTap, this.pad = EdgeInsets.zero});
  final List<HudFab> fabs;
  final void Function(String id) onTap;
  final EdgeInsets pad;

  static const _bottomReserve = 24.0;

  static Size _span(HudFab f, Size area, EdgeInsets pad) => Size(
        (area.width - pad.left - pad.right - f.size).clamp(0.0, area.width).toDouble(),
        (area.height - pad.top - pad.bottom - f.size - _bottomReserve).clamp(0.0, area.height).toDouble(),
      );

  static Offset place(HudFab f, Size area, EdgeInsets pad) {
    final span = _span(f, area, pad);
    return Offset(pad.left + f.x * span.width, pad.top + f.y * span.height);
  }

  static HudFab moved(HudFab f, Offset delta, Size area, EdgeInsets pad) {
    final span = _span(f, area, pad);
    final at = place(f, area, pad) + delta;
    return HudFab(
      id: f.id,
      x: span.width <= 0 ? f.x : ((at.dx - pad.left) / span.width).clamp(0.0, 1.0).toDouble(),
      y: span.height <= 0 ? f.y : ((at.dy - pad.top) / span.height).clamp(0.0, 1.0).toDouble(),
      size: f.size,
    );
  }

  static Widget button(HudFab f, VoidCallback onPressed, {Object? heroTag}) {
    return FloatingActionButton(
      heroTag: heroTag,
      onPressed: onPressed,
      child: Icon(iconFor(f.id), size: (f.size * 0.42).clamp(18.0, 36.0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (fabs.isEmpty) return const SizedBox.shrink();
    final area = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        for (final f in fabs)
          Positioned(
            left: place(f, area, pad).dx,
            top: place(f, area, pad).dy,
            width: f.size,
            height: f.size,
            child: button(f, () => onTap(f.id), heroTag: 'hud-${f.id}-${f.x}-${f.y}'),
          ),
      ],
    );
  }

  static String labelFor(String id) => switch (id) {
        'hdr' => 'HDR',
        'playlist' => 'Playlist',
        'more' => 'More',
        _ => AppSettings.allQuickActions[id] ?? id,
      };

  static IconData iconFor(String id) => switch (id) {
        'hdr' => Icons.hdr_on,
        'eq' => Icons.equalizer,
        'playlist' => Icons.queue_music,
        'more' => Icons.more_vert,
        'search' => Icons.search,
        'refresh' => Icons.refresh,
        'select' => Icons.checklist,
        'sort' => Icons.sort,
        'speed' => Icons.speed,
        'background' => Icons.headphones_outlined,
        'screenshot' => Icons.camera_alt_outlined,
        'lock' => Icons.lock_outline,
        'aspect' => Icons.aspect_ratio,
        'ab' => Icons.repeat,
        'bookmark' => Icons.bookmark_outline,
        'brightness' => Icons.brightness_6_outlined,
        'rotate' => Icons.screen_rotation,
        'share' => Icons.share_outlined,
        'night' => Icons.nights_stay_outlined,
        'zoom' => Icons.zoom_in,
        'popup' => Icons.picture_in_picture_alt,
        'timer' => Icons.timer_outlined,
        'properties' => Icons.info_outline,
        'playopt' => Icons.tune,
        'decoder' => Icons.memory,
        'mirror' => Icons.flip,
        'invert' => Icons.invert_colors,
        'repeat' => Icons.queue_music,
        'delete' => Icons.delete_outline,
        'cast' => Icons.cast,
        'navbar' => Icons.navigation_outlined,
        'caption' => Icons.closed_caption_outlined,
        'captionSettings' => Icons.manage_accounts_outlined,
        'color' => Icons.color_lens_outlined,
        _ => Icons.play_arrow,
      };
}

class HudEditorPage extends StatefulWidget {
  const HudEditorPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<HudEditorPage> createState() => _HudEditorPageState();
}

class _HudEditorPageState extends State<HudEditorPage> {
  late List<HudFab> _fabs;
  bool _dirty = false;
  bool _landscape = true;
  int? _active;

  @override
  void initState() {
    super.initState();
    _fabs = decodeHud(appSettings.hudFabsJson);
  }

  void _close() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      SystemNavigator.pop();
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('You have unsaved floating action button changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (r == 'save') {
      await _save();
      return true;
    }
    return r == 'discard';
  }

  Future<void> _save() async {
    appSettings.hudFabsJson = encodeHud(_fabs);
    await appSettings.save();
    _dirty = false;
    widget.onChanged();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save success'),
        content: const Text('Floating action button layout saved.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _add() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('Add from More', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              ListTile(title: const Text('HDR'), leading: const Icon(Icons.hdr_on), onTap: () => Navigator.pop(ctx, 'hdr')),
              ListTile(title: const Text('Playlist'), leading: const Icon(Icons.queue_music), onTap: () => Navigator.pop(ctx, 'playlist')),
              ListTile(title: const Text('More'), leading: const Icon(Icons.more_vert), onTap: () => Navigator.pop(ctx, 'more')),
              for (final e in AppSettings.allQuickActions.entries)
                ListTile(title: Text(e.value), leading: Icon(HudLayer.iconFor(e.key)), onTap: () => Navigator.pop(ctx, e.key)),
            ],
          ),
        );
      },
    );
    if (id == null) return;
    setState(() {
      _fabs.add(HudFab(id: id, x: 0.8, y: 0.72, size: 56));
      _dirty = true;
      _active = _fabs.length - 1;
    });
  }

  void _replace(int i, HudFab f) {
    setState(() {
      _fabs[i] = f;
      _dirty = true;
    });
  }

  Widget _preview(Size area) {
    return FittedBox(
      child: SizedBox.fromSize(
        size: area,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _active = null),
                  child: const _PlayerMock(),
                ),
              ),
              for (var i = 0; i < _fabs.length; i++)
                Positioned(
                  left: HudLayer.place(_fabs[i], area, EdgeInsets.zero).dx,
                  top: HudLayer.place(_fabs[i], area, EdgeInsets.zero).dy,
                  width: _fabs[i].size,
                  height: _fabs[i].size,
                  child: GestureDetector(
                    onPanStart: (_) => setState(() => _active = i),
                    onPanUpdate: (d) => _replace(i, HudLayer.moved(_fabs[i], d.delta, area, EdgeInsets.zero)),
                    child: Container(
                      foregroundDecoration: _active == i ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)) : null,
                      child: HudLayer.button(_fabs[i], () => setState(() => _active = i)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final i = _active;
    final f = (i != null && i < _fabs.length) ? _fabs[i] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.stay_current_landscape), label: Text('Landscape')),
              ButtonSegment(value: false, icon: Icon(Icons.stay_current_portrait), label: Text('Portrait')),
            ],
            selected: {_landscape},
            onSelectionChanged: (v) => setState(() => _landscape = v.first),
          ),
          if (f == null || i == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Drag a button to place it. Tap one to resize or remove it.', style: Theme.of(context).textTheme.bodySmall),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(HudLayer.iconFor(f.id)),
              title: Text(HudLayer.labelFor(f.id)),
              subtitle: Slider(
                min: 40,
                max: 96,
                divisions: 7,
                label: '${f.size.round()}',
                value: f.size.clamp(40.0, 96.0).toDouble(),
                onChanged: (v) => _replace(i, HudFab(id: f.id, x: f.x, y: f.y, size: v)),
              ),
              trailing: IconButton(
                color: Theme.of(context).colorScheme.error,
                onPressed: () => setState(() {
                  _fabs.removeAt(i);
                  _active = null;
                  _dirty = true;
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = MediaQuery.sizeOf(context);
    final area = _landscape ? Size(device.longestSide, device.shortestSide) : Size(device.shortestSide, device.longestSide);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Navigator.canPop(context)
              ? null
              : BackButton(onPressed: () async {
                  if (await _confirmLeave() && mounted) _close();
                }),
          title: const Text('Floating action buttons'),
          actions: [
            IconButton(tooltip: 'Add', onPressed: _add, icon: const Icon(Icons.add)),
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(child: _preview(area)),
                ),
              ),
              _panel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerMock extends StatelessWidget {
  const _PlayerMock();

  @override
  Widget build(BuildContext context) {
    const light = TextStyle(color: Colors.white, fontSize: 14);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF263238), Colors.black],
            ),
          ),
        ),
        const Center(child: Icon(Icons.movie_outlined, size: 96, color: Colors.white12)),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 56,
          child: ColoredBox(
            color: Colors.black38,
            child: Row(
              children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.keyboard_arrow_down, color: Colors.white)),
                const Expanded(child: Text('Video title', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                for (final id in appSettings.titleActions)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(HudLayer.iconFor(id), color: Colors.white, size: 22)),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ColoredBox(
            color: Colors.black38,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Text('00:12', style: light),
                      Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: LinearProgressIndicator(value: 0.3))),
                      Text('-00:30', style: light),
                    ],
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.skip_previous, color: Colors.white, size: 32),
                      SizedBox(width: 16),
                      Icon(Icons.play_circle, color: Colors.white, size: 56),
                      SizedBox(width: 16),
                      Icon(Icons.skip_next, color: Colors.white, size: 32),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class TitleBarEditor extends StatefulWidget {
  const TitleBarEditor({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<TitleBarEditor> createState() => _TitleBarEditorState();
}

class _TitleBarEditorState extends State<TitleBarEditor> {
  late List<String> order;
  late Set<String> enabled;

  static const catalog = <String, String>{
    'hdr': 'HDR',
    'playlist': 'Playlist',
    'more': 'More',
    ...AppSettings.allQuickActions,
  };

  @override
  void initState() {
    super.initState();
    enabled = appSettings.titleActions.toSet();
    order = [...appSettings.titleActions];
    for (final id in catalog.keys) {
      if (!order.contains(id)) order.add(id);
    }
  }

  Future<void> _persist() async {
    var next = order.where(enabled.contains).toList();
    if (next.isEmpty) next = ['more'];
    appSettings.titleActions = next;
    await appSettings.save();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(leading: standaloneBack(context), title: const Text('Title bar buttons')),
      body: ReorderableListView.builder(
        padding: EdgeInsets.only(bottom: pad.bottom + 24),
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
            title: Text(catalog[id] ?? id),
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

String encodeHud(List<HudFab> list) => jsonEncode(list.map((e) => e.toJson()).toList());

List<HudFab> decodeHud(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) => HudFab.fromJson(Map<String, dynamic>.from(e as Map))).where((e) => e.id != 'pick' && e.id != 'subtitle').toList();
  } catch (_) {
    return [];
  }
}
