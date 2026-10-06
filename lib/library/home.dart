import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/core/crash.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/library/library.dart';
import 'package:video_player_app/main.dart';
import 'package:video_player_app/mini/mini_player.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/player/player.dart';
import 'package:video_player_app/player/player_route.dart';
import 'package:video_player_app/playback/session.dart';
import 'package:video_player_app/settings/settings.dart';
import 'package:video_player_app/settings/settings_ui.dart';
import 'package:video_player_app/core/widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSettingsChanged});
  final VoidCallback onSettingsChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _snackHost = GlobalKey();
  int tab = 0;
  bool loading = true;
  String? error;
  bool selecting = false;
  final selected = <String>{};
  LayoutMode layout = LayoutMode.list;
  SortBy sort = SortBy.date;
  bool sortDesc = true;
  String query = '';
  bool searching = false;
  final searchCtrl = TextEditingController();
  String filter = 'all';
  Timer? refreshTimer;
  Timer? libraryDebounce;
  StreamSubscription<Map<String, dynamic>>? events;

  String? folderPath;
  final folderTrail = <String>[];
  bool _miniPlaying = false;
  int _openGen = 0;
  String? _lastOpenPath;
  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
    events = AndroidBridge.events().listen(_onEvent);
    refreshTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!mounted || !appSettings.autoRefresh) return;
      _refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    libraryDebounce?.cancel();
    events?.cancel();
    PlaybackSession.onMutated = null;
    try {
      PlaybackSession.controller?.removeListener(_onSessionTick);
    } catch (_) {}
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _consumePending() async {
    final path = await AndroidBridge.pendingOpen();
    if (path != null && path.isNotEmpty && mounted) {
      await _openPath(path);
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    final type = e['type'] as String? ?? '';
    if (type == 'open') {
      final path = e['path'] as String?;
      if (path != null) _openPath(path);
    } else if (type == 'media') {
      final action = e['action'] as String? ?? '';
      if (action == 'refresh') {
        _onLibraryChanged();
        return;
      }
      if (!PlaybackSession.active) return;
      final c = PlaybackSession.controller;
      switch (action) {
        case 'play':
          unawaited(AndroidBridge.requestAudioFocus());
          c?.setVolume(1);
          unawaited(AndroidBridge.setStereoVolume(appSettings.audioBalanceLeft, appSettings.audioBalanceRight));
          unawaited(c?.play() ?? Future<void>.value());
        case 'pause':
          c?.pause();
        case 'duck':
          c?.setVolume(0.2);
        case 'unduck':
          c?.setVolume(1);
          unawaited(AndroidBridge.setStereoVolume(appSettings.audioBalanceLeft, appSettings.audioBalanceRight));
        case 'next':
          unawaited(PlaybackSession.skip(1));
        case 'prev':
          unawaited(PlaybackSession.skip(-1));
        case 'seek':
          final ms = e['positionMs'];
          if (ms is num) unawaited(c?.seekTo(Duration(milliseconds: ms.round())) ?? Future<void>.value());
      }
      if (mounted) setState(() {});
    }
  }

  void _onLibraryChanged() {
    if (!mounted || !appSettings.autoRefresh) return;
    libraryDebounce?.cancel();
    libraryDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || !appSettings.autoRefresh) return;
      unawaited(_refresh());
    });
  }

  bool _busy = false;

  Future<void> _boot({bool spinner = true}) async {
    if (_busy) return;
    _busy = true;
    if (spinner && library.videos.isEmpty && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await library.requestPermissions();
      if (appSettings.scanOnStart || appSettings.autoRefresh || !spinner) {
        await library.scan();
      }
    } catch (e, s) {
      error = '$e';
      CrashLog.record('LIBRARY', '$e', s);
      if (mounted) showAllFilesFailed(context, 'Read');
    }
    _busy = false;
    if (mounted) setState(() => loading = false);
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      await library.scan();
    } catch (e, s) {
      CrashLog.record('LIBRARY', '$e', s);
    }
    _busy = false;
    if (mounted) setState(() {});
  }

  List<VideoItem> get visible => library.sorted(sort, desc: sortDesc, query: query, filter: filter);

  List<String> get tabs => appSettings.visibleTabs;

  int get safeTab {
    if (tabs.isEmpty) return 0;
    return tab.clamp(0, tabs.length - 1);
  }

  Future<void> _open(VideoItem item, {List<VideoItem>? playlist}) async {
    final now = DateTime.now();
    if (_lastOpenPath == item.path && now.difference(_lastOpenAt) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastOpenPath = item.path;
    _lastOpenAt = now;
    final gen = ++_openGen;
    await CrashLog.breadcrumb('Play ${item.path}');
    if (!mounted) return;
    final nav = Navigator.of(context);
    final reuse = PlaybackSession.controller != null &&
        PlaybackSession.controller!.hasPlayer &&
        PlaybackSession.item?.path == item.path;

    PlaybackSession.replacing = true;
    try {
      if (nav.canPop()) nav.popUntil((r) => r.isFirst);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      PlaybackSession.replacing = false;
    }
    if (!mounted || gen != _openGen) return;
    if (!reuse) await PlaybackSession.stop();
    if (!mounted || gen != _openGen) return;

    final list = playlist ?? visible;
    final i = list.indexWhere((v) => v.id == item.id);
    await nav.push(PlayerSlideRoute(
      page: PlayerPage(
        playlist: list,
        index: i < 0 ? 0 : i,
        onChanged: () => setState(() {}),
      ),
    ));
    if (gen != _openGen) return;
    _bindSession();
    if (mounted) setState(() {});
  }

  void _bindSession() {
    try {
      PlaybackSession.controller?.removeListener(_onSessionTick);
    } catch (_) {}
    PlaybackSession.controller?.addListener(_onSessionTick);
    PlaybackSession.onMutated = () {
      if (!mounted) return;
      try {
        PlaybackSession.controller?.removeListener(_onSessionTick);
      } catch (_) {}
      PlaybackSession.controller?.addListener(_onSessionTick);
      _miniPlaying = PlaybackSession.controller?.value.isPlaying ?? false;
      setState(() {});
    };
    _miniPlaying = PlaybackSession.controller?.value.isPlaying ?? false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      unawaited(PlaybackSession.onAway());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(PlaybackSession.onBack());
      unawaited(() async {
        final had = library.allFiles;
        library.allFiles = await AndroidBridge.hasAllFilesAccess();
        if (library.allFiles && !had && mounted) await _boot(spinner: false);
      }());
    }
  }

  void _onSessionTick() {
    final p = PlaybackSession.controller?.value.isPlaying ?? false;
    if (p != _miniPlaying && mounted) {
      _miniPlaying = p;
      setState(() {});
    }
  }

  Future<void> _openPath(String path) async {
    if (!looksLikeVideo(path)) {
      if (mounted) {
        SlideSnackBar.show(context, message: 'That file is not a playable video', behavior: SnackBarBehavior.floating);
      }
      return;
    }
    VideoItem? item;
    for (final v in library.videos) {
      if (v.path == path) item = v;
    }
    final content = path.startsWith('content:');
    item ??= VideoItem(
      id: path,
      path: path,
      title: content ? 'Imported video' : p.basename(path),
      folder: content ? 'Imported' : p.dirname(path),
      size: content ? 0 : (File(path).existsSync() ? File(path).lengthSync() : 0),
      modified: DateTime.now(),
    );
    if (library.videos.every((v) => v.path != path)) {
      library.videos.add(item);
    }
    await _open(item, playlist: [item, ...visible.where((v) => v.path != path)]);
  }

  Future<void> _sessionSkip(int delta) => PlaybackSession.skip(delta);

  void _toggleSelect(VideoItem item) {
    setState(() {
      selecting = true;
      if (selected.contains(item.id)) {
        selected.remove(item.id);
      } else {
        selected.add(item.id);
      }
    });
  }

  void _toggleMasterVisible() {
    _toggleMaster(visible.map((v) => v.id));
  }

  void _toggleFolder(String folderPath) {
    final ids = library.videos
        .where((v) => v.folder == folderPath || v.path.startsWith('$folderPath/'))
        .map((v) => v.id)
        .toList();
    setState(() {
      selecting = true;
      if (ids.isEmpty) return;
      final allOn = ids.every(selected.contains);
      if (allOn) {
        selected.removeAll(ids);
      } else {
        selected.addAll(ids);
      }
    });
  }

  void _toggleMasterFolder() {
    final path = folderPath;
    if (path == null) {
      _toggleMaster(library.videos.map((v) => v.id));
      return;
    }
    final ids = library.listDir(path).whereType<File>().map((e) {
      for (final v in library.videos) {
        if (v.path == e.path) return v.id;
      }
      return e.path;
    });
    _toggleMaster(ids);
  }

  void _toggleMaster(Iterable<String> ids) {
    final list = ids.toList();
    setState(() {
      selecting = true;
      final allOn = list.isNotEmpty && list.every(selected.contains);
      selected.clear();
      if (!allOn) selected.addAll(list);
    });
  }

  Future<void> _deleteSelected() async {
    final items = library.videos.where((v) => selected.contains(v.id)).toList();
    if (items.isEmpty) return;
    final ok = !appSettings.confirmDelete || await confirm(context, 'Delete ${items.length} videos?', 'This cannot be undone.');
    if (ok != true) return;
    final done = await library.deleteVideos(items);
    if (!done && mounted) showAllFilesFailed(context, 'Delete');
    setState(() {
      selected.clear();
      selecting = false;
    });
  }

  Future<void> _shareSelected() async {
    final items = library.videos.where((v) => selected.contains(v.id)).toList();
    if (items.isEmpty) return;
    await SharePlus.instance.share(ShareParams(files: items.map((e) => XFile(e.path)).toList()));
  }

  List<VideoItem> _selectedVideos() {
    final out = <VideoItem>[];
    for (final id in selected) {
      VideoItem? found;
      for (final v in library.videos) {
        if (v.id == id || v.path == id) found = v;
      }
      found ??= VideoItem(
        id: id,
        path: id,
        title: p.basename(id),
        folder: p.dirname(id),
        size: File(id).existsSync() ? File(id).lengthSync() : 0,
        modified: DateTime.now(),
      );
      out.add(found);
    }
    return out;
  }

  Future<void> _holdVideo(VideoItem item, {required bool folderActions}) async {
    if (selecting) {
      if (!selected.contains(item.id)) _toggleSelect(item);
      await _openSelectionMenu(folderActions: folderActions);
      return;
    }
    await showItemsMenu(
      context,
      items: [item],
      folderActions: folderActions,
      allowRename: true,
      onChanged: () { if (mounted) setState(() {}); },
      onPlay: (items) => _open(items.first, playlist: items),
    );
  }

  Future<void> _openSelectionMenu({required bool folderActions}) async {
    final items = _selectedVideos();
    if (items.isEmpty) return;
    await showItemsMenu(
      context,
      items: items,
      folderActions: folderActions,
      allowRename: folderActions && items.length == 1,
      fromSelection: true,
      onChanged: () {
        if (!mounted) return;
        setState(() {
          selected.removeWhere((id) => library.videos.every((v) => v.id != id && v.path != id));
          if (selected.isEmpty) selecting = false;
        });
      },
      onPlay: (items) {
        setState(() {
          selecting = false;
          selected.clear();
        });
        unawaited(_open(items.first, playlist: items));
      },
    );
  }

  void _openHiddenTab(String id) {
    final dest = switch (id) {
      'videos' => VideosHub(
          loading: loading,
          layout: layout,
          sort: sort,
          sortDesc: sortDesc,
          query: query,
          searching: searching,
          searchCtrl: searchCtrl,
          selecting: selecting,
          selected: selected,
          items: visible,
          onSearch: (_) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchPage(onOpen: _open, onToggleSelect: _toggleSelect),
            ));
          },
          onQuery: (v) => setState(() => query = v),
          onLayout: (v) => setState(() => layout = v),
          onSort: _sortSheet,
          onOpen: _open,
          onToggleSelect: _toggleSelect,
          onHold: (item) => _holdVideo(item, folderActions: false),
          onSelectionHold: () => _openSelectionMenu(folderActions: false),
          onShareSelected: _shareSelected,
          onDeleteSelected: _deleteSelected,
          onClearSelect: () => setState(() {
            selecting = false;
            selected.clear();
          }),
          onSelectMode: () => setState(() => selecting = true),
          onToggleMaster: _toggleMasterVisible,
          onRefresh: _refresh,
          overflow: _overflowItems(includeSelect: true),
          onOverflow: _onOverflow,
          filter: filter,
          onFilter: (v) => setState(() => filter = v),
        ),
      'folders' => FoldersHub(
          loading: loading,
          folderPath: folderPath,
          folderTrail: folderTrail,
          onPath: (path, trail) => setState(() {
            folderPath = path;
            folderTrail
              ..clear()
              ..addAll(trail);
          }),
          onOpen: _open,
          onToggleSelect: _toggleSelect,
          onHoldVideo: (item) => _holdVideo(item, folderActions: true),
          onSelectionHold: () => _openSelectionMenu(folderActions: true),
          selecting: selecting,
          selected: selected,
          onSelectMode: () => setState(() => selecting = true),
          onToggleMaster: _toggleMasterFolder,
          onToggleFolder: _toggleFolder,
          onClearSelect: () => setState(() {
            selecting = false;
            selected.clear();
          }),
          onShareSelected: _shareSelected,
          onDeleteSelected: _deleteSelected,
          overflow: _overflowItems(includeSelect: false),
          onOverflow: _onOverflow,
          onRefresh: _refresh,
        ),
      'settings' => SettingsHub(onChanged: widget.onSettingsChanged),
      _ => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        body: dest,
        floatingActionButton: id == 'folders' ? _pasteFab(forceFolders: true) : null,
      ),
    ));
  }

  Widget? _pasteFab({bool forceFolders = false}) {
    final onFolders = forceFolders || (tabs.isNotEmpty && tabs[safeTab] == 'folders');
    if (!onFolders || folderPath == null || !library.hasClipboard) return null;
    return FloatingActionButton(
      onPressed: () async {
        final dir = folderPath;
        if (dir == null) return;
        final ok = await library.pasteInto(dir);
        if (!ok && mounted) showAllFilesFailed(context, 'Paste');
        if (mounted) setState(() {});
      },
      tooltip: library.clipCut ? 'Move here' : 'Paste',
      child: Icon(library.clipCut ? Icons.drive_file_move_outline : Icons.content_paste),
    );
  }

  List<PopupMenuEntry<String>> _overflowItems({bool includeSelect = false}) {
    final hidden = appSettings.hiddenTabs;
    return [
      const PopupMenuItem(value: 'eq', child: Text('Equalizer')),
      const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
      if (includeSelect) const PopupMenuItem(value: 'select', child: Text('Select')),
      const PopupMenuItem(value: 'crash', child: Text('Crash report')),
      for (final id in hidden)
        PopupMenuItem(value: 'tab:$id', child: Text(AppSettings.tabLabels[id] ?? id)),
    ];
  }

  Future<void> _onOverflow(String v) async {
    if (v == 'eq') {
      try {
        await CrashLog.breadcrumb('Open equalizer');
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerPage()));
      } catch (e, s) {
        CrashLog.record('EQ', '$e', s);
      }
    } else if (v == 'refresh') {
      await _refresh();
    } else if (v == 'select') {
      setState(() => selecting = true);
    } else if (v == 'crash') {
      await CrashLog.show();
    } else if (v.startsWith('tab:')) {
      _openHiddenTab(v.substring(4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 840;
    final current = tabs.isEmpty ? 'videos' : tabs[safeTab];

    Widget pageFor(String id) {
      switch (id) {
        case 'folders':
          return PopScope(
            canPop: folderPath == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (folderTrail.length <= 1) {
                setState(() {
                  folderPath = null;
                  folderTrail.clear();
                });
              } else {
                final next = List<String>.from(folderTrail)..removeLast();
                setState(() {
                  folderPath = next.last;
                  folderTrail
                    ..clear()
                    ..addAll(next);
                });
              }
            },
            child: FoldersHub(
              loading: loading,
              folderPath: folderPath,
              folderTrail: folderTrail,
              onPath: (path, trail) => setState(() {
                folderPath = path;
                folderTrail
                  ..clear()
                  ..addAll(trail);
              }),
              onOpen: _open,
              onToggleSelect: _toggleSelect,
              onHoldVideo: (item) => _holdVideo(item, folderActions: true),
          onSelectionHold: () => _openSelectionMenu(folderActions: true),
              selecting: selecting,
              selected: selected,
              onSelectMode: () => setState(() => selecting = true),
              onToggleMaster: _toggleMasterFolder,
              onToggleFolder: _toggleFolder,
              onClearSelect: () => setState(() {
                selecting = false;
                selected.clear();
              }),
              onShareSelected: _shareSelected,
              onDeleteSelected: _deleteSelected,
              overflow: _overflowItems(includeSelect: false),
              onOverflow: _onOverflow,
              onRefresh: _refresh,
            ),
          );
        case 'settings':
          return SettingsHub(onChanged: widget.onSettingsChanged);
        default:
          return VideosHub(
            loading: loading,
            layout: layout,
            sort: sort,
            sortDesc: sortDesc,
            query: query,
            searching: searching,
            searchCtrl: searchCtrl,
            selecting: selecting,
            selected: selected,
            items: visible,
            onSearch: (_) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SearchPage(onOpen: _open, onToggleSelect: _toggleSelect),
              ));
            },
            onQuery: (v) => setState(() => query = v),
            onLayout: (v) => setState(() => layout = v),
            onSort: _sortSheet,
            onOpen: _open,
            onToggleSelect: _toggleSelect,
            onHold: (item) => _holdVideo(item, folderActions: false),
            onSelectionHold: () => _openSelectionMenu(folderActions: false),
            onShareSelected: _shareSelected,
            onDeleteSelected: _deleteSelected,
            onClearSelect: () => setState(() {
              selecting = false;
              selected.clear();
            }),
            onSelectMode: () => setState(() => selecting = true),
            onToggleMaster: _toggleMasterVisible,
            onRefresh: _refresh,
            overflow: _overflowItems(includeSelect: true),
            onOverflow: _onOverflow,
            filter: filter,
            onFilter: (v) => setState(() => filter = v),
          );
      }
    }

    NavigationDestination dest(String id) {
      return switch (id) {
        'folders' => const NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Folders'),
        'settings' => const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        _ => const NavigationDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: 'Videos'),
      };
    }

    NavigationRailDestination rail(String id) {
      return switch (id) {
        'folders' => const NavigationRailDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: Text('Folders')),
        'settings' => const NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')),
        _ => const NavigationRailDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: Text('Videos')),
      };
    }

    final body = pageFor(current);
    final pad = SystemBars.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    if (onTop) {
      SystemBars.alwaysHide = false;
      SystemBars.apply(icons: dark ? Brightness.light : Brightness.dark, contrast: false, hide: false);
    }

    Widget shell(Widget child) {
      // Everything the mini player draws (including its parked, off-edge state)
      // is clipped to the content area, so it can never spill over the
      // navigation rail or past the screen edge.
      return ClipRect(
        child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          child,
          if (PlaybackSession.active && appSettings.inAppMiniplayer)
            Offstage(
              offstage: !onTop,
              child: IgnorePointer(
                ignoring: !onTop,
                child: MiniPlayerOverlay(
                  pad: pad,
                  // With the bottom NavigationBar the body already ends above
                  // it, so nothing extra is needed. Without it (wide layout or a
                  // single tab) the body runs under the system nav bar.
                  bottomInset: !wide && tabs.length > 1 ? 0.0 : pad.bottom,
                  onExpand: () {
                    final item = PlaybackSession.item;
                    final list = PlaybackSession.playlist;
                    if (item == null) return;
                    PlaybackSession.transferring = true;
                    PlaybackSession.keepAlive = false;
                    setState(() {});
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      unawaited(_open(item, playlist: list));
                    });
                  },
                  onClose: () async {
                    await PlaybackSession.stop();
                    if (mounted) setState(() {});
                  },
                  onPrev: () => _sessionSkip(-1),
                  onNext: () => _sessionSkip(1),
                ),
              ),
            ),
        ],
        ),
      );
    }

    if (wide) {
      return Scaffold(
        body: SlideSnackBarHost(
          key: _snackHost,
          child: Padding(
          padding: EdgeInsets.only(left: pad.left, right: pad.right),
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: safeTab,
                onDestinationSelected: (i) => setState(() {
                  tab = i;
                  selecting = false;
                  selected.clear();
                  searching = false;
                }),
                labelType: NavigationRailLabelType.all,
                destinations: [for (final id in tabs) rail(id)],
              ),
              const VerticalDivider(width: 1),
              // Mini player is scoped to the content, never over the rail.
              Expanded(child: shell(body)),
            ],
          ),
          ),
        ),
        floatingActionButton: _pasteFab(),
      );
    }

    return Scaffold(
      body: SlideSnackBarHost(
        key: _snackHost,
        child: Padding(
          padding: EdgeInsets.only(left: pad.left, right: pad.right),
          child: shell(body),
        ),
      ),
      floatingActionButton: _pasteFab(),
      bottomNavigationBar: tabs.length <= 1
          ? null
          : NavigationBar(
              selectedIndex: safeTab,
              onDestinationSelected: (i) => setState(() {
                tab = i;
                selecting = false;
                selected.clear();
                searching = false;
              }),
              destinations: [for (final id in tabs) dest(id)],
            ),
      backgroundColor: scheme.surface,
    );
  }

  Future<void> _sortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Sort by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              for (final s in SortBy.values)
                RadioListTile<SortBy>(
                  value: s,
                  groupValue: sort,
                  title: Text(switch (s) {
                    SortBy.name => 'Name',
                    SortBy.date => 'Date',
                    SortBy.size => 'Size',
                    SortBy.duration => 'Duration',
                    SortBy.folder => 'Folder',
                  }),
                  onChanged: (v) {
                    setState(() => sort = v!);
                    Navigator.pop(ctx);
                  },
                ),
              SwitchListTile(
                title: const Text('Descending'),
                value: sortDesc,
                onChanged: (v) {
                  setState(() => sortDesc = v);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class VideosHub extends StatelessWidget {
  const VideosHub({
    super.key,
    required this.loading,
    required this.layout,
    required this.sort,
    required this.sortDesc,
    required this.query,
    required this.searching,
    required this.searchCtrl,
    required this.selecting,
    required this.selected,
    required this.items,
    required this.onSearch,
    required this.onQuery,
    required this.onLayout,
    required this.onSort,
    required this.onOpen,
    required this.onToggleSelect,
    required this.onHold,
    required this.onSelectionHold,
    required this.onShareSelected,
    required this.onDeleteSelected,
    required this.onClearSelect,
    required this.onSelectMode,
    required this.onToggleMaster,
    required this.onRefresh,
    required this.overflow,
    this.onOverflow,
    this.filter = 'all',
    this.onFilter,
  });

  final bool loading;
  final LayoutMode layout;
  final SortBy sort;
  final bool sortDesc;
  final String query;
  final bool searching;
  final TextEditingController searchCtrl;
  final bool selecting;
  final Set<String> selected;
  final List<VideoItem> items;
  final void Function(bool) onSearch;
  final void Function(String) onQuery;
  final void Function(LayoutMode) onLayout;
  final Future<void> Function() onSort;
  final Future<void> Function(VideoItem item, {List<VideoItem>? playlist}) onOpen;
  final void Function(VideoItem) onToggleSelect;
  final Future<void> Function(VideoItem) onHold;
  final Future<void> Function() onSelectionHold;
  final Future<void> Function() onShareSelected;
  final Future<void> Function() onDeleteSelected;
  final VoidCallback onClearSelect;
  final VoidCallback onSelectMode;
  final VoidCallback onToggleMaster;
  final Future<void> Function() onRefresh;
  final List<PopupMenuEntry<String>> overflow;
  final Future<void> Function(String)? onOverflow;
  final String filter;
  final void Function(String)? onFilter;

  /// Grid sized from the width the grid really gets (not the screen width, which
  /// includes the navigation rail). Phones keep the original 2-column cards;
  /// tablets and landscape get as many columns as fit, with shorter thumbnails
  /// so more rows are visible.
  SliverGridDelegate _gridDelegate(double width) {
    const gap = 12.0;
    if (width < 600) {
      return const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        childAspectRatio: 0.82,
      );
    }
    final avail = width - 24;
    final cols = ((avail + gap) / (200 + gap)).floor().clamp(3, 8).toInt();
    final cardW = (avail - gap * (cols - 1)) / cols;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      // 16:10 thumbnail + the text footer (about 80 dp).
      mainAxisExtent: cardW * 0.625 + 80,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    return LibraryRefresh(
      displacement: 40,
      edgeOffset: pad.top + kToolbarHeight,
      onRefresh: onRefresh,
      child: NestedScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      headerSliverBuilder: (context, inner) {
        return [
          SliverAppBar(
            pinned: true,
            title: selecting
                ? GestureDetector(
                    onLongPress: onSelectionHold,
                    child: Text('${selected.length} selected'),
                  )
                : const Text('Videos'),
            actions: [
              if (selecting)
                IconButton(onPressed: onClearSelect, icon: const Icon(Icons.close), tooltip: 'Cancel')
              else ...[
                IconButton(onPressed: () => onSearch(true), icon: const Icon(Icons.search), tooltip: 'Search'),
                if (overflow.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (v) => onOverflow?.call(v),
                    itemBuilder: (_) => overflow,
                  ),
              ],
            ],
          ),
          if (library.videos.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: LayoutBuilder(
                builder: (context, box) {
                  final inline = box.maxWidth >= 600;
                  final count = Text(
                    '${items.length} videos  ·  ${formatBytes(library.totalBytes)}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  );
                  final actions = <Widget>[
                    if (selecting)
                      Checkbox(
                        value: items.isNotEmpty && items.every((v) => selected.contains(v.id)),
                        onChanged: items.isEmpty ? null : (_) => onToggleMaster(),
                      )
                    else ...[
                      IconButton(
                        tooltip: layout == LayoutMode.list ? 'Grid' : 'List',
                        onPressed: () => onLayout(layout == LayoutMode.list ? LayoutMode.grid : LayoutMode.list),
                        icon: Icon(layout == LayoutMode.list ? Icons.grid_view : Icons.view_list),
                      ),
                      IconButton(
                        tooltip: 'Sort',
                        onPressed: onSort,
                        icon: const Icon(Icons.sort),
                      ),
                    ],
                  ];
                  final chips = ChipScroller(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: filter == 'all',
                        onSelected: (_) => onFilter?.call('all'),
                      ),
                      ChoiceChip(
                        label: const Text('Bookmarked'),
                        selected: filter == 'bookmarked',
                        onSelected: (_) => onFilter?.call('bookmarked'),
                      ),
                      ChoiceChip(
                        label: const Text('Pinned'),
                        selected: filter == 'pinned',
                        onSelected: (_) => onFilter?.call('pinned'),
                      ),
                    ],
                  );
                  // Wide content: count, filters and view buttons share one row,
                  // leaving more of the screen for the videos.
                  if (inline) {
                    return Row(
                      children: [
                        count,
                        const SizedBox(width: 20),
                        Expanded(child: chips),
                        ...actions,
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(children: [Expanded(child: count), ...actions]),
                      chips,
                    ],
                  );
                },
              ),
            ),
          ),
        ];
      },
      body: loading
          ? ListView(
              key: const ValueKey('videos-loading'),
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              children: const [SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))],
            )
          : library.videos.isEmpty
              ? CustomScrollView(
                  key: const ValueKey('empty-library-scroll'),
                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyLibrary(key: const ValueKey('empty-library'), onRefresh: onRefresh),
                    ),
                  ],
                )
              : items.isEmpty
                  ? CustomScrollView(
                      key: const ValueKey('no-matches-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text('No video found', style: TextStyle(color: scheme.onSurfaceVariant)),
                          ),
                        ),
                      ],
                    )
                  : layout == LayoutMode.list
                      ? ListView.builder(
                          key: const ValueKey('video-list'),
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.only(bottom: 24 + pad.bottom),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            return VideoListTile(
                              item: item,
                              selected: selected.contains(item.id),
                              selecting: selecting,
                              onTap: () => selecting ? onToggleSelect(item) : onOpen(item),
                              onLongPress: () => onHold(item),
                            );
                          },
                        )
                      : LayoutBuilder(
                          key: const ValueKey('video-grid'),
                          builder: (context, box) => GridView.builder(
                            physics: const ClampingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + pad.bottom),
                            gridDelegate: _gridDelegate(box.maxWidth),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];
                              return VideoGridCard(
                                item: item,
                                selected: selected.contains(item.id),
                                selecting: selecting,
                                onTap: () => selecting ? onToggleSelect(item) : onOpen(item),
                                onLongPress: () => onHold(item),
                              );
                            },
                          ),
                        ),
    ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({super.key, required this.onRefresh});
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final granted = library.allFiles;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_filter_outlined, size: 56, color: scheme.outline),
              const SizedBox(height: 12),
              Text(
                granted ? 'No videos on this device' : 'Need storage access',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                granted
                    ? 'Nothing playable turned up in internal storage, SD cards, or USB drives. Copy videos onto the device, then scan again.'
                    : 'Grant all-files access so the player can read internal storage, SD cards, and USB drives.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (!granted)
                FilledButton(
                  onPressed: () async {
                    await library.ensureAllFiles();
                    await onRefresh();
                  },
                  child: const Text('Grant access'),
                )
              else
                FilledButton(onPressed: onRefresh, child: const Text('Scan again')),
            ],
          ),
        ),
      ),
    );
  }
}

class FoldersHub extends StatelessWidget {
  const FoldersHub({
    super.key,
    required this.loading,
    required this.folderPath,
    required this.folderTrail,
    required this.onPath,
    required this.onOpen,
    required this.onToggleSelect,
    required this.onHoldVideo,
    this.onSelectionHold,
    required this.selecting,
    this.selected = const {},
    this.onSelectMode,
    this.onToggleMaster,
    this.onToggleFolder,
    this.onClearSelect,
    this.onShareSelected,
    this.onDeleteSelected,
    this.overflow = const [],
    this.onOverflow,
    required this.onRefresh,
  });

  final bool loading;
  final String? folderPath;
  final List<String> folderTrail;
  final void Function(String? path, List<String> trail) onPath;
  final Future<void> Function(VideoItem item, {List<VideoItem>? playlist}) onOpen;
  final void Function(VideoItem) onToggleSelect;
  final Future<void> Function(VideoItem) onHoldVideo;
  final Future<void> Function()? onSelectionHold;
  final bool selecting;
  final Set<String> selected;
  final VoidCallback? onSelectMode;
  final VoidCallback? onToggleMaster;
  final void Function(String folderPath)? onToggleFolder;
  final VoidCallback? onClearSelect;
  final Future<void> Function()? onShareSelected;
  final Future<void> Function()? onDeleteSelected;
  final List<PopupMenuEntry<String>> overflow;
  final Future<void> Function(String)? onOverflow;
  final Future<void> Function() onRefresh;

  bool _folderOn(String folderPath) {
    final ids = library.videos.where((v) => v.folder == folderPath || v.path.startsWith('$folderPath/')).map((v) => v.id);
    return ids.isNotEmpty && ids.every(selected.contains);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    final roots = library.volumes;
    final path = folderPath;
    if (path == null) {
      return LibraryRefresh(
        displacement: 52,
        onRefresh: onRefresh,
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            title: selecting
                ? GestureDetector(
                    onLongPress: onSelectionHold,
                    child: Text('${selected.length} selected'),
                  )
                : const Text('Folders'),
            actions: [
              if (selecting)
                IconButton(onPressed: onClearSelect, icon: const Icon(Icons.close), tooltip: 'Cancel')
              else ...[
                IconButton(
                  tooltip: 'Select',
                  onPressed: onSelectMode,
                  icon: const Icon(Icons.checklist),
                ),
                if (overflow.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (v) => onOverflow?.call(v),
                    itemBuilder: (_) => overflow,
                  ),
              ],
            ],
          ),
          if (loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + pad.bottom + (library.hasClipboard ? 80 : 0)),
              sliver: SliverList.list(children: [
                if (roots.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.sd_storage_outlined),
                    title: const Text('Internal storage'),
                    subtitle: const Text('Tap to browse'),
                    onTap: () => onPath('/storage/emulated/0', ['/storage/emulated/0']),
                  ),
                for (final v in roots)
                  Card(
                    child: ListTile(
                      leading: Icon(v.isUsb ? Icons.usb : v.isSd ? Icons.sd_card : Icons.smartphone_outlined),
                      title: Text(v.description),
                      subtitle: Text(
                        [
                          v.path,
                          if (v.isUsb) 'USB',
                          if (v.isSd) 'SD card',
                          v.state,
                        ].join(' · '),
                      ),
                      onTap: () => onPath(v.path, [v.path]),
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Libraries', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final f in library.folders)
                  ListTile(
                    leading: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        onSelectMode?.call();
                        onToggleFolder?.call(f.path);
                      },
                      child: const SizedBox(width: 40, height: 40, child: Icon(Icons.folder_outlined)),
                    ),
                    title: Text(f.name),
                    subtitle: Text('${f.videoCount} videos · ${formatBytes(f.size)}'),
                    selected: selecting && _folderOn(f.path),
                    trailing: selecting
                        ? Checkbox(
                            value: _folderOn(f.path),
                            onChanged: (_) => onToggleFolder?.call(f.path),
                          )
                        : null,
                    onTap: () => selecting ? onToggleFolder?.call(f.path) : onPath(f.path, [f.path]),
                  ),
              ]),
            ),
        ],
      ),
      );
    }

    final ents = library.listDir(path);
    final files = ents.whereType<File>().toList();
    final fileIds = files.map((e) {
      for (final v in library.videos) {
        if (v.path == e.path) return v.id;
      }
      return e.path;
    }).toList();
    final allOn = fileIds.isNotEmpty && fileIds.every(selected.contains);
    return Column(
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          title: selecting
              ? GestureDetector(
                  onLongPress: onSelectionHold,
                  child: Text('${selected.length} selected'),
                )
              : Text(p.basename(path).isEmpty ? path : p.basename(path)),
          actions: [
            if (selecting)
              IconButton(onPressed: onClearSelect, icon: const Icon(Icons.close), tooltip: 'Cancel')
            else ...[
              IconButton(
                tooltip: 'Select',
                onPressed: onSelectMode,
                icon: const Icon(Icons.checklist),
              ),
              if (overflow.isNotEmpty)
                PopupMenuButton<String>(
                  onSelected: (v) => onOverflow?.call(v),
                  itemBuilder: (_) => overflow,
                ),
            ],
          ],
        ),
        if (selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${files.length} videos',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
                Checkbox(
                  value: allOn,
                  onChanged: files.isEmpty ? null : (_) => onToggleMaster?.call(),
                ),
              ],
            ),
          ),
        Expanded(
          child: LibraryRefresh(
            displacement: 40,
            edgeOffset: 8,
            onRefresh: onRefresh,
            child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            padding: EdgeInsets.only(bottom: pad.bottom + 16 + (library.hasClipboard ? 80 : 0)),
            itemCount: ents.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return ListTile(
                  leading: const Icon(Icons.drive_folder_upload),
                  title: const Text('Up'),
                  subtitle: Text(folderTrail.length <= 1 ? 'Storage' : p.basename(folderTrail[folderTrail.length - 2])),
                  onTap: () {
                    if (folderTrail.length <= 1) {
                      onPath(null, []);
                    } else {
                      final next = List<String>.from(folderTrail)..removeLast();
                      onPath(next.last, next);
                    }
                  },
                );
              }
              final e = ents[i - 1];
              final name = p.basename(e.path);
              final isDir = e is Directory;
              VideoItem? video;
              if (!isDir) {
                for (final v in library.videos) {
                  if (v.path == e.path) video = v;
                }
                video ??= VideoItem(
                  id: e.path,
                  path: e.path,
                  title: name,
                  folder: path,
                  size: (e as File).existsSync() ? e.lengthSync() : 0,
                  modified: e.statSync().modified,
                );
              }
              return ListTile(
                leading: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    onSelectMode?.call();
                    if (isDir) {
                      onToggleFolder?.call(e.path);
                    } else if (video != null) {
                      onToggleSelect(video);
                    }
                  },
                  child: isDir
                      ? const SizedBox(width: 40, height: 40, child: Icon(Icons.folder))
                      : SizedBox(width: 56, height: 36, child: video != null ? VideoThumb(item: video, radius: 6) : const Icon(Icons.movie_outlined)),
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: isDir ? const Text('Folder') : Text(formatBytes(video?.size ?? 0)),
                selected: isDir ? selecting && _folderOn(e.path) : video != null && selected.contains(video.id),
                trailing: selecting
                    ? Checkbox(
                        value: isDir ? _folderOn(e.path) : video != null && selected.contains(video.id),
                        onChanged: (_) {
                          if (isDir) {
                            onToggleFolder?.call(e.path);
                          } else if (video != null) {
                            onToggleSelect(video);
                          }
                        },
                      )
                    : null,
                onLongPress: () {
                  if (isDir) {
                    showFolderEntryMenu(
                      context,
                      path: e.path,
                      isDir: true,
                      onChanged: () => onRefresh(),
                      onOpen: () => onPath(e.path, [...folderTrail, e.path]),
                    );
                    return;
                  }
                  if (video != null) onHoldVideo(video);
                },
                onTap: () {
                  if (selecting) {
                    if (isDir) {
                      onToggleFolder?.call(e.path);
                    } else if (video != null) {
                      onToggleSelect(video);
                    }
                    return;
                  }
                  if (isDir) {
                    onPath(e.path, [...folderTrail, e.path]);
                  } else if (video != null) {
                    final vids = ents.whereType<File>().map((f) {
                      VideoItem? found;
                      for (final v in library.videos) {
                        if (v.path == f.path) found = v;
                      }
                      return found ??
                          VideoItem(
                            id: f.path,
                            path: f.path,
                            title: p.basename(f.path),
                            folder: path,
                            size: f.lengthSync(),
                            modified: f.statSync().modified,
                          );
                    }).toList();
                    onOpen(video, playlist: vids);
                  }
                },
              );
            },
          ),
          ),
        ),
      ],
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.onOpen, required this.onToggleSelect});
  final Future<void> Function(VideoItem item, {List<VideoItem>? playlist}) onOpen;
  final void Function(VideoItem) onToggleSelect;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ctrl = TextEditingController();
  String query = '';

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = library.sorted(SortBy.name, desc: false, query: query);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search videos', border: InputBorder.none),
          onChanged: (v) => setState(() => query = v),
        ),
      ),
      body: items.isEmpty
          ? const Center(child: Text('No matches'))
          : ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + 24),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return VideoListTile(
                  item: item,
                  selected: false,
                  selecting: false,
                  onTap: () => widget.onOpen(item, playlist: items),
                  onLongPress: () => showItemsMenu(
                    context,
                    items: [item],
                    allowRename: true,
                    onChanged: () { if (mounted) setState(() {}); },
                    onPlay: (picked) => widget.onOpen(picked.first, playlist: items),
                  ),
                );
              },
            ),
    );
  }
}
