import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/library/library.dart';
import 'package:video_player_app/main.dart';
import 'package:video_player_app/core/models.dart';

class VideoThumb extends StatefulWidget {
  const VideoThumb({super.key, required this.item, this.radius = 12});
  final VideoItem item;
  final double radius;

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) _load();
  }

  Future<void> _load() async {
    final id = widget.item.id;
    final data = await library.thumbnailFor(widget.item);
    if (!mounted || widget.item.id != id) return;
    if (identical(data, _bytes)) return;
    setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: _bytes != null
                ? Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 360, filterQuality: FilterQuality.low)
                : Icon(Icons.movie_outlined, color: scheme.onSurfaceVariant),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                formatDuration(widget.item.duration),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showAllFilesFailed(BuildContext context, String action) {
  if (!context.mounted) return;
  SlideSnackBar.show(context, message: 'Failed to $action. Make sure you have all file access Enabled', behavior: SnackBarBehavior.floating);
}

class LibraryRefresh extends StatelessWidget {
  const LibraryRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
    this.displacement = 40,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double edgeOffset;
  final double displacement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHigh,
      displacement: displacement,
      edgeOffset: edgeOffset,
      strokeWidth: 2.4,
      notificationPredicate: (n) => n.depth <= 1,
      onRefresh: onRefresh,
      child: child,
    );
  }
}

class ResumeBar extends StatelessWidget {
  const ResumeBar({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.01) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress.clamp(0, 1).toDouble(),
        minHeight: 3,
        color: scheme.primary,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

class VideoListTile extends StatelessWidget {
  const VideoListTile({
    super.key,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onTap,
    this.onLongPress,
  });

  final VideoItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.45) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 128,
                height: 72,
                child: VideoThumb(item: item, radius: 10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25)),
                    const SizedBox(height: 4),
                    Text(
                      '${formatBytes(item.size)}  ·  ${DateFormat.yMMMd().format(item.modified)}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    if (appSettings.pinned.contains(item.path) || item.bookmarked)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (appSettings.pinned.contains(item.path))
                              Icon(Icons.push_pin, size: 14, color: scheme.primary),
                            if (item.bookmarked || appSettings.bookmarks.contains(item.path))
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.bookmark, size: 14, color: scheme.primary),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    ResumeBar(progress: item.progress),
                  ],
                ),
              ),
              if (selecting)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onTap(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoGridCard extends StatelessWidget {
  const VideoGridCard({
    super.key,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onTap,
    this.onLongPress,
  });

  final VideoItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.7) : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: VideoThumb(item: item, radius: 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25)),
                        const SizedBox(height: 4),
                        Text(
                          formatBytes(item.size),
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        ResumeBar(progress: item.progress),
                      ],
                    ),
                  ),
                  if (selecting)
                    Checkbox(
                      value: selected,
                      onChanged: (_) => onTap(),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that can be dragged between a minimum and a maximum height.
///
/// [initial] is the opening height and [maxSize] the hard upper limit (both fractions of the
/// screen). With [fitContent] (default) the maximum is also capped at the height the content
/// actually needs, so a short menu can never be dragged out into a mostly empty full-screen sheet;
/// long content still scrolls inside the sheet up to [maxSize].
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required List<Widget> Function(BuildContext ctx) children,
  double initial = 0.56,
  double maxSize = 0.95,
  bool fitContent = true,
}) {
  final pad = SystemBars.rawOf(context);
  final bottomBar = SystemBars.bottomInset(context);
  // Landscape phones are short: open the sheet (nearly) full height so the
  // actions are not cut off, and keep it a readable width on wide screens.
  final short = MediaQuery.sizeOf(context).height < 520;
  final cap = maxSize.clamp(0.38, 0.95).toDouble();
  final startSize = (short ? cap : initial).clamp(0.38, cap).toDouble();
  return SystemBars.modal(
    () => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 640),
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: pad.left, right: pad.right),
        child: _FitSheet(
          start: startSize,
          max: cap,
          fit: fitContent,
          bottomPad: bottomBar,
          children: () => children(ctx),
        ),
      ),
    ),
  );
}

/// Draggable sheet body for [showAppSheet]: measures its content once laid out and lowers the
/// maximum size to fit it (never below [_minFloor], never above [max]).
class _FitSheet extends StatefulWidget {
  const _FitSheet({
    required this.start,
    required this.max,
    required this.fit,
    required this.bottomPad,
    required this.children,
  });
  final double start;
  final double max;
  final bool fit;
  final double bottomPad;
  final List<Widget> Function() children;

  @override
  State<_FitSheet> createState() => _FitSheetState();
}

class _FitSheetState extends State<_FitSheet> {
  static const _minFloor = 0.28;
  // Drag handle block (8 + 4 + 8) plus the list's own bottom padding (12).
  static const _chrome = 32.0;

  final _contentKey = GlobalKey();
  double? _fitted;

  void _measure(double available) {
    if (!widget.fit || available <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _contentKey.currentContext?.size?.height;
      if (h == null) return;
      final frac = ((h + _chrome) / available).clamp(_minFloor, widget.max).toDouble();
      if (_fitted == null || (frac - _fitted!).abs() > 0.003) setState(() => _fitted = frac);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sheet = LayoutBuilder(
      builder: (context, box) {
        _measure(box.maxHeight);
        final cap = _fitted ?? widget.max;
        final low = cap < _minFloor ? cap : _minFloor;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: widget.start.clamp(low, cap).toDouble(),
          minChildSize: low,
          maxChildSize: cap,
          builder: (_, sc) {
            return Material(
              color: scheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    key: _contentKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    // The sheet ends above the navigation bar (its last row can never sit under the bar's buttons);
    // the bar area itself is painted with the sheet colour so it still looks like one surface.
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(padding: EdgeInsets.only(bottom: widget.bottomPad), child: sheet),
        if (widget.bottomPad > 0)
          Positioned(left: 0, right: 0, bottom: 0, height: widget.bottomPad, child: ColoredBox(color: scheme.surface)),
      ],
    );
  }
}

Future<void> showItemsMenu(
  BuildContext context, {
  required List<VideoItem> items,
  required VoidCallback onChanged,
  required void Function(List<VideoItem> items) onPlay,
  bool folderActions = false,
  bool allowRename = false,
  bool fromSelection = false,
}) async {
  if (items.isEmpty) return;
  final scheme = Theme.of(context).colorScheme;
  final many = items.length > 1;
  final playLabel = folderActions
      ? 'Play queue selected'
      : (fromSelection ? 'Play selected' : 'Play');
  final allBookmarked = items.every((e) => e.bookmarked || appSettings.bookmarks.contains(e.path));
  final allPinned = items.every((e) => appSettings.pinned.contains(e.path));
  await showAppSheet<void>(
    context: context,
    initial: 0.72,
    children: (ctx) => [
      ListTile(
        leading: many
            ? CircleAvatar(child: Text('${items.length}'))
            : SizedBox(width: 64, height: 40, child: VideoThumb(item: items.first, radius: 8)),
        title: Text(
          many ? '${items.length} selected' : items.first.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(many ? formatBytes(items.fold<int>(0, (n, v) => n + v.size)) : formatBytes(items.first.size)),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.play_arrow),
        title: Text(playLabel),
        onTap: () {
          Navigator.pop(ctx);
          onPlay(items);
        },
      ),
      if (allowRename && !many)
        ListTile(
          leading: const Icon(Icons.drive_file_rename_outline),
          title: const Text('Rename'),
          onTap: () async {
            Navigator.pop(ctx);
            await Future<void>.delayed(const Duration(milliseconds: 160));
            if (!context.mounted) return;
            final item = items.first;
            final name = await promptRename(context, item.title);
            if (name != null) {
              final next = await library.rename(item, name);
              if (next == null && context.mounted) showAllFilesFailed(context, 'Rename');
              onChanged();
            }
          },
        ),
      if (folderActions) ...[
        ListTile(
          leading: const Icon(Icons.copy),
          title: const Text('Copy'),
          onTap: () {
            Navigator.pop(ctx);
            library.copyEntries(items.map((e) => e.path));
            onChanged();
          },
        ),
        ListTile(
          leading: const Icon(Icons.content_cut),
          title: const Text('Cut'),
          onTap: () {
            Navigator.pop(ctx);
            library.cutEntries(items.map((e) => e.path));
            onChanged();
          },
        ),
      ],
      ListTile(
        leading: const Icon(Icons.share_outlined),
        title: const Text('Share'),
        onTap: () async {
          Navigator.pop(ctx);
          await SharePlus.instance.share(ShareParams(files: items.map((e) => XFile(e.path)).toList()));
        },
      ),
      ListTile(
        leading: Icon(allBookmarked ? Icons.bookmark : Icons.bookmark_outline),
        title: Text(allBookmarked ? 'Remove bookmark' : 'Bookmark'),
        onTap: () {
          Navigator.pop(ctx);
          for (final item in items) {
            if (allBookmarked) {
              appSettings.bookmarks.remove(item.path);
              item.bookmarked = false;
            } else {
              appSettings.bookmarks.add(item.path);
              item.bookmarked = true;
            }
          }
          appSettings.save();
          onChanged();
        },
      ),
      ListTile(
        leading: Icon(allPinned ? Icons.push_pin : Icons.push_pin_outlined),
        title: Text(allPinned ? 'Unpin' : 'Pin'),
        onTap: () {
          Navigator.pop(ctx);
          for (final item in items) {
            if (allPinned) {
              appSettings.pinned.remove(item.path);
            } else {
              appSettings.pinned.add(item.path);
            }
          }
          appSettings.save();
          onChanged();
        },
      ),
      ListTile(
        leading: Icon(Icons.delete_outline, color: scheme.error),
        title: Text('Delete', style: TextStyle(color: scheme.error)),
        onTap: () async {
          Navigator.pop(ctx);
          final ok = !appSettings.confirmDelete ||
              await confirm(context, many ? 'Delete ${items.length} videos?' : 'Delete this video?', many ? 'This cannot be undone.' : items.first.title);
          if (ok == true) {
            final done = await library.deleteVideos(items);
            if (!done && context.mounted) showAllFilesFailed(context, 'Delete');
            onChanged();
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Properties'),
        onTap: () async {
          Navigator.pop(ctx);
          await Future<void>.delayed(const Duration(milliseconds: 160));
          if (!context.mounted) return;
          if (!many) {
            showProperties(context, items.first);
            return;
          }
          showAppSheet<void>(
            context: context,
            initial: 0.4,
            children: (c) => [
              const ListTile(title: Text('Properties')),
              ListTile(title: const Text('Items'), subtitle: Text('${items.length}')),
              ListTile(title: const Text('Total size'), subtitle: Text(formatBytes(items.fold<int>(0, (n, v) => n + v.size)))),
            ],
          );
        },
      ),
    ],
  );
}
Future<void> showProperties(BuildContext context, VideoItem item) async {
  final file = File(item.path);
  final exists = file.existsSync();
  final stat = exists ? await file.stat() : null;
  var size = item.size;
  if (exists) {
    try {
      final n = file.lengthSync();
      if (n > 0) size = n;
    } catch (_) {}
  }
  if (size <= 0) size = await AndroidBridge.fileSize(item.path);
  final info = await AndroidBridge.mediaInfo(item.path);
  if (!context.mounted) return;
  final fps = (info?['fps'] as num?)?.toDouble() ?? item.fps;
  final bitrate = (info?['bitrate'] as num?)?.toInt() ?? item.bitrate;
  final frames = (info?['frameCount'] as num?)?.toInt() ?? item.frameCount;
  final width = (info?['width'] as num?)?.toInt() ?? item.width;
  final height = (info?['height'] as num?)?.toInt() ?? item.height;
  final durationMs = (info?['durationMs'] as num?)?.toInt();
  String fpsLabel;
  if (fps == null || fps <= 0) {
    fpsLabel = '-';
  } else if ((fps - fps.round()).abs() < 0.05) {
    fpsLabel = '${fps.round()} fps';
  } else {
    fpsLabel = '${fps.toStringAsFixed(2)} fps';
  }
  final rows = <(String, String)>[
    ('Name', item.title),
    ('Path', item.path),
    ('Folder', item.folder),
    ('Size', '${formatBytes(size)}  ($size bytes)'),
    ('Duration', durationMs != null ? formatDuration(Duration(milliseconds: durationMs)) : formatDuration(item.duration)),
    ('Resolution', width > 0 && height > 0 ? '$width×$height' : item.resolutionLabel),
    ('Width', '$width px'),
    ('Height', '$height px'),
    ('Frame rate', fpsLabel),
    ('Frame count', frames != null && frames > 0 ? '$frames' : '-'),
    ('Bitrate', bitrate != null && bitrate > 0 ? '${(bitrate / 1000).toStringAsFixed(0)} kbps' : '-'),
    ('Aspect', width > 0 && height > 0 ? (width / height).toStringAsFixed(4) : '-'),
    ('Container', item.extension.toUpperCase()),
    ('MIME', item.mime ?? (info?['mime'] as String?) ?? 'video/${item.extension}'),
    ('Created', item.created != null ? DateFormat.yMMMMd().add_Hms().format(item.created!) : '-'),
    ('Modified', DateFormat.yMMMMd().add_Hms().format(stat?.modified ?? item.modified)),
    ('Accessed', stat != null ? DateFormat.yMMMMd().add_Hms().format(stat.accessed) : '-'),
    ('Changed', stat != null ? DateFormat.yMMMMd().add_Hms().format(stat.changed) : '-'),
    ('Exists', exists ? 'Yes' : 'Missing'),
    ('Readable', exists ? 'Yes' : 'No'),
    ('Bookmarked', item.bookmarked ? 'Yes' : 'No'),
    ('Resume', '${(item.progress * 100).toStringAsFixed(1)}%'),
    ('Storage', item.path.contains('usb') ? 'USB / OTG' : item.path.contains('sdcard') || item.path.contains('/storage/') && !item.path.contains('emulated') ? 'SD card / volume' : 'Internal'),
  ];
  await showAppSheet<void>(
    context: context,
    initial: 0.78,
    children: (ctx) => [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
        child: Row(
          children: [
            const Expanded(child: Text('Properties', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
          ],
        ),
      ),
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(rows[i].$1, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
              Expanded(child: SelectableText(rows[i].$2, style: const TextStyle(fontWeight: FontWeight.w500))),
            ],
          ),
        ),
      ],
    ],
  );
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final scheme = Theme.of(context).colorScheme;
  final v = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return v ?? false;
}

Future<String?> promptText(BuildContext context, String title, String initial, {String? error}) async {
  final c = TextEditingController(text: initial);
  try {
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        final pad = SystemBars.rawOf(context);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + insets.bottom + pad.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(border: const OutlineInputBorder(), errorText: error, errorMaxLines: 3),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
                ],
              ),
            ],
          ),
        );
      },
    );
  } finally {
    c.dispose();
  }
}

/// Asks for a new name until it is acceptable (see [renameError]); null when cancelled or unchanged.
Future<String?> promptRename(BuildContext context, String current, {bool isDir = false}) async {
  var initial = current;
  String? error;
  while (true) {
    final input = await promptText(context, 'Rename', initial, error: error);
    if (input == null) return null;
    final name = input.trim();
    if (name == current) return null;
    error = renameError(name, current, isDir: isDir);
    if (error == null) return name;
    initial = name;
    if (!context.mounted) return null;
  }
}

class ChipScroller extends StatelessWidget {
  const ChipScroller({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

Future<void> showFolderEntryMenu(
  BuildContext context, {
  required String path,
  required bool isDir,
  required VoidCallback onChanged,
  VoidCallback? onOpen,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final name = path.split(RegExp(r'[/\\]')).last;
  await showAppSheet<void>(
    context: context,
    initial: 0.56,
    children: (ctx) => [
      ListTile(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(isDir ? 'Folder' : 'Video')),
      if (onOpen != null)
        ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text(isDir ? 'Open' : 'Play'),
          onTap: () {
            Navigator.pop(ctx);
            onOpen();
          },
        ),
      ListTile(
        leading: const Icon(Icons.drive_file_rename_outline),
        title: const Text('Rename'),
        onTap: () async {
          Navigator.pop(ctx);
          await Future<void>.delayed(const Duration(milliseconds: 160));
          if (!context.mounted) return;
          final next = await promptRename(context, name, isDir: isDir);
          if (next != null) {
            final dest = await AndroidBridge.renamePath(path, next);
            if (dest == null && context.mounted) showAllFilesFailed(context, 'Rename');
            onChanged();
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.copy),
        title: const Text('Copy'),
        onTap: () {
          Navigator.pop(ctx);
          library.copyEntry(path);
          onChanged();
        },
      ),
      ListTile(
        leading: const Icon(Icons.content_cut),
        title: const Text('Cut'),
        onTap: () {
          Navigator.pop(ctx);
          library.cutEntry(path);
          onChanged();
        },
      ),
      ListTile(
        leading: Icon(Icons.delete_outline, color: scheme.error),
        title: Text('Delete', style: TextStyle(color: scheme.error)),
        onTap: () async {
          Navigator.pop(ctx);
          final ok = !appSettings.confirmDelete || await confirm(context, 'Delete ${isDir ? 'folder' : 'video'}?', name);
          if (ok == true) {
            final done = await library.deletePath(path);
            if (!done && context.mounted) showAllFilesFailed(context, 'Delete');
            onChanged();
          }
        },
      ),
    ],
  );
}

/// Opens [route] as its own activity (system slide transition); if that activity is unavailable,
/// pushes [fallback] inside the app instead.
Future<void> openPage(BuildContext context, String route, Widget Function() fallback) async {
  if (await AndroidBridge.openRoute(route)) return;
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => fallback()));
}
