import 'package:flutter/material.dart';

import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/core/widgets.dart';
import 'package:video_player_app/main.dart';
import 'package:video_player_app/native/android_bridge.dart';

class VideoPickerPage extends StatefulWidget {
  const VideoPickerPage({super.key});

  @override
  State<VideoPickerPage> createState() => _VideoPickerPageState();
}

class _VideoPickerPageState extends State<VideoPickerPage> {
  bool _loading = true;
  bool _allowMultiple = false;
  bool _busy = false;
  String _query = '';
  final _selected = <String>{};
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    _allowMultiple = await AndroidBridge.pickerAllowMultiple();
    try {
      await library.requestPermissions();
      await library.scan();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    try {
      await library.scan();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  List<VideoItem> get _items => library.sorted(SortBy.date, desc: true, query: _query);

  Future<void> _cancel() async {
    await AndroidBridge.cancelPick();
  }

  Future<void> _pick(VideoItem item) async {
    if (_busy) return;
    if (_allowMultiple) {
      setState(() {
        if (_selected.contains(item.id)) {
          _selected.remove(item.id);
        } else {
          _selected.add(item.id);
        }
      });
      return;
    }
    _busy = true;
    final ok = await AndroidBridge.completePick(path: item.path);
    _busy = false;
    if (!ok && mounted) {
      SlideSnackBar.show(context, message: 'Could not share that video', behavior: SnackBarBehavior.floating);
    }
  }

  Future<void> _done() async {
    if (_busy) return;
    final paths = _items.where((v) => _selected.contains(v.id)).map((v) => v.path).toList();
    if (paths.isEmpty) {
      await _cancel();
      return;
    }
    _busy = true;
    final ok = await AndroidBridge.completePick(paths: paths);
    _busy = false;
    if (!ok && mounted) {
      SlideSnackBar.show(context, message: 'Could not share those videos', behavior: SnackBarBehavior.floating);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = SystemBars.rawOf(context);
    final items = _items;
    final selecting = _allowMultiple;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Choose a video',
              border: InputBorder.none,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          leading: IconButton(
            tooltip: 'Close',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (selecting)
              TextButton(
                onPressed: _selected.isEmpty ? _cancel : _done,
                child: Text(_selected.isEmpty ? 'Cancel' : 'Done (${_selected.length})'),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : library.videos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.movie_filter_outlined, size: 56, color: scheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            library.allFiles ? 'No videos on this device' : 'Need storage access',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            library.allFiles
                                ? 'Copy videos onto the device, then scan again.'
                                : 'Grant all-files access so this picker can list videos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 20),
                          if (!library.allFiles)
                            FilledButton(
                              onPressed: () async {
                                await library.ensureAllFiles();
                                await _refresh();
                              },
                              child: const Text('Grant access'),
                            )
                          else
                            FilledButton(onPressed: _refresh, child: const Text('Scan again')),
                        ],
                      ),
                    ),
                  )
                : LibraryRefresh(
                    onRefresh: _refresh,
                    child: items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 220,
                                child: Center(
                                  child: Text('No video found', style: TextStyle(color: scheme.onSurfaceVariant)),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                            padding: EdgeInsets.only(bottom: 24 + pad.bottom),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];
                              return VideoListTile(
                                item: item,
                                selected: _selected.contains(item.id),
                                selecting: selecting,
                                onTap: () => _pick(item),
                              );
                            },
                          ),
                  ),
      ),
    );
  }
}
