import 'dart:convert';

import 'package:flutter/material.dart';

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
  const HudLayer({super.key, required this.fabs, required this.onTap, this.pad = EdgeInsets.zero, this.bottomReserve = 88});
  final List<HudFab> fabs;
  final void Function(String id) onTap;
  final EdgeInsets pad;
  final double bottomReserve;

  @override
  Widget build(BuildContext context) {
    if (fabs.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          for (final f in fabs)
            Positioned(
              left: pad.left + f.x * (size.width - pad.left - pad.right - f.size).clamp(0.0, size.width),
              top: pad.top + f.y * (size.height - pad.top - pad.bottom - f.size - bottomReserve).clamp(0.0, size.height),
              width: f.size,
              height: f.size,
              child: FloatingActionButton(
                heroTag: 'hud-${f.id}-${f.x}-${f.y}',
                onPressed: () => onTap(f.id),
                child: Icon(iconFor(f.id), size: (f.size * 0.42).clamp(18.0, 36.0)),
              ),
            ),
        ],
      ),
    );
  }

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
  int? _active;

  @override
  void initState() {
    super.initState();
    _fabs = decodeHud(appSettings.hudFabsJson);
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
        final pad = MediaQuery.viewPaddingOf(ctx);
        return ListView(
          padding: EdgeInsets.only(bottom: pad.bottom + 16),
          children: [
            const ListTile(title: Text('Add from More', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            ListTile(title: const Text('HDR'), leading: const Icon(Icons.hdr_on), onTap: () => Navigator.pop(ctx, 'hdr')),
            ListTile(title: const Text('Playlist'), leading: const Icon(Icons.queue_music), onTap: () => Navigator.pop(ctx, 'playlist')),
            ListTile(title: const Text('More'), leading: const Icon(Icons.more_vert), onTap: () => Navigator.pop(ctx, 'more')),
            for (final e in AppSettings.allQuickActions.entries)
              ListTile(title: Text(e.value), leading: Icon(HudLayer.iconFor(e.key)), onTap: () => Navigator.pop(ctx, e.key)),
          ],
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

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101418),
        appBar: AppBar(
          title: const Text('Floating action buttons'),
          actions: [
            IconButton(tooltip: 'Add', onPressed: _add, icon: const Icon(Icons.add)),
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(),
              ),
            ),
            for (var i = 0; i < _fabs.length; i++)
              _HudHandle(
                fab: _fabs[i],
                selected: _active == i,
                pad: pad,
                screen: size,
                onSelect: () => setState(() => _active = i),
                onChange: (f) => setState(() {
                  _fabs[i] = f;
                  _dirty = true;
                }),
                onDelete: () => setState(() {
                  _fabs.removeAt(i);
                  _active = null;
                  _dirty = true;
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _HudHandle extends StatelessWidget {
  const _HudHandle({
    required this.fab,
    required this.selected,
    required this.pad,
    required this.screen,
    required this.onSelect,
    required this.onChange,
    required this.onDelete,
  });
  final HudFab fab;
  final bool selected;
  final EdgeInsets pad;
  final Size screen;
  final VoidCallback onSelect;
  final ValueChanged<HudFab> onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final maxW = (screen.width - pad.left - pad.right - fab.size).clamp(1.0, screen.width);
    final maxH = (screen.height - pad.top - pad.bottom - fab.size - 120).clamp(1.0, screen.height);
    final left = pad.left + fab.x * maxW;
    final top = pad.top + 48 + fab.y * maxH;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onSelect,
        onPanUpdate: (d) {
          onChange(HudFab(
            id: fab.id,
            x: ((left + d.delta.dx - pad.left) / maxW).clamp(0.0, 1.0),
            y: ((top + d.delta.dy - pad.top - 48) / maxH).clamp(0.0, 1.0),
            size: fab.size,
          ));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: fab.size,
              height: fab.size,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: selected ? Border.all(color: Colors.white, width: 3) : null,
              ),
              child: Icon(HudLayer.iconFor(fab.id), color: Theme.of(context).colorScheme.onPrimary),
            ),
            if (selected)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    color: Colors.white,
                    onPressed: () => onChange(HudFab(id: fab.id, x: fab.x, y: fab.y, size: (fab.size - 8).clamp(40.0, 96.0))),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    color: Colors.white,
                    onPressed: () => onChange(HudFab(id: fab.id, x: fab.x, y: fab.y, size: (fab.size + 8).clamp(40.0, 96.0))),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(color: Colors.redAccent, onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      appBar: AppBar(title: const Text('Title bar buttons')),
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
