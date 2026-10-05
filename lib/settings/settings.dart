import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:video_player_app/core/models.dart';

final appSettings = AppSettings();

class AppSettings {
  ThemeModePref themeMode = ThemeModePref.system;
  int seedColor = 0xFF38618D;
  bool dynamicColor = false;
  PlaylistUiStyle playlistStyle = PlaylistUiStyle.sheet;

  // General
  bool rememberPlayback = true;
  bool confirmDelete = true;
  bool scanOnStart = true;
  bool autoRefresh = true;
  bool showHiddenFolders = false;
  bool skipNomedia = true;

  // Display in playback
  bool showRemaining = true;
  bool showClock = true;
  bool showBattery = true;
  bool showSeekPreview = true;

  // Orientation
  RotationLock rotation = RotationLock.none;

  // Playback
  DecoderMode decoder = DecoderMode.hw;
  bool hwPriority = true;
  int seekStepSeconds = 10;
  bool autoMiniplayer = false;
  bool inAppMiniplayer = true;
  bool rememberBackgroundPlay = false;
  bool backgroundPlay = false;
  bool rememberAspect = true;
  AspectMode aspect = AspectMode.fit;
  bool resumePlayback = true;
  bool rememberSpeed = false;
  double speed = 1;
  bool rememberBrightness = false;
  double brightness = -1;
  bool longPress2x = true;
  bool longPressVibration = true;
  bool doubleTapSeek = true;
  bool autoPlayNext = true;
  bool gestureControl = true;
  bool allowZoom = true;
  bool rememberHdr = false;
  bool hdrOn = true;
  bool pitchShift = false;

  PlayMode playMode = PlayMode.order;

  // Accessibility
  bool highContrast = false;
  bool reduceMotion = false;
  bool largeControls = false;
  bool colorBlindDeuteranopia = false;
  bool colorBlindProtanopia = false;
  bool colorBlindTritanopia = false;
  bool grayscale = false;
  bool invertColors = false;
  bool nightMode = false;
  double nightWarmth = 0.35;
  bool extraDim = false;
  bool boldText = false;
  double uiScale = 1;

  // Filters
  double contrast = 1;
  double saturation = 1;
  double gamma = 1;
  double hueRotate = 0;
  bool mirror = false;
  bool colorCorrection = false;
  bool alwaysHideNavBar = false;
  bool developerEnabled = false;
  bool debugLog = false;
  bool videoLogOverlay = false;
  bool videoLogShowState = true;
  bool videoLogShowMedia = true;
  bool videoLogShowRender = true;
  bool videoLogShowDecoder = true;
  bool videoLogShowTiming = false;
  bool logPlayerEvents = false;
  bool logGestureEvents = false;
  bool logLifecycleEvents = false;

  /// Tab ids hidden from the bottom bar and moved into the overflow menu.
  /// Valid: videos, folders, settings. At least one tab must stay visible.
  List<String> hiddenTabs = [];

  static const tabIds = <String>['videos', 'folders', 'settings'];

  static const tabLabels = <String, String>{
    'videos': 'Videos',
    'folders': 'Folders',
    'settings': 'Settings',
  };

  static const defaultQuickActions = <String>['screenshot', 'background', 'speed'];

  static const allQuickActions = <String, String>{
    'speed': 'Speed',
    'background': 'Background',
    'screenshot': 'Screenshot',
    'lock': 'Lock',
    'aspect': 'Screen mode',
    'ab': 'A-B repeat',
    'eq': 'Equalizer',
    'volume': 'Volume',
    'bookmark': 'Bookmark',
    'brightness': 'Brightness',
    'rotate': 'Rotate',
    'share': 'Share',
    'night': 'Night mode',
    'zoom': 'Zoom',
    'skipBack': 'Seek back',
    'skipForward': 'Seek forward',
    'popup': 'PIP',
    'color': 'Color',
    'timer': 'Timer',
    'properties': 'Properties',
    'playopt': 'Play option',
    'decoder': 'Decoder',
    'mirror': 'Mirror',
    'invert': 'Invert',
    'repeat': 'Playlist',
    'delete': 'Delete',
    'cast': 'Cast',
    'navbar': 'Hide navigation bar',
  };

  List<String> quickActions = List<String>.from(defaultQuickActions);

  static const defaultTitleActions = <String>['hdr', 'eq', 'playlist', 'more'];
  List<String> titleActions = List<String>.from(defaultTitleActions);
  String hudFabsJson = '[]';

  static const eqBandHz = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  static const eqPresets = <String, List<int>>{
    'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Bass': [900, 700, 400, 150, 0, 0, -50, 0, 0, 0],
    'Treble': [0, 0, 0, 0, 50, 150, 350, 550, 750, 850],
    'Vocal': [-200, -100, 80, 420, 560, 420, 120, 0, -80, -160],
    'Rock': [450, 320, 180, 0, -120, 80, 280, 420, 320, 220],
    'Pop': [-80, 180, 380, 280, 0, -80, 220, 320, 220, 40],
    'Jazz': [280, 180, 40, 180, 280, 180, 40, 180, 280, 180],
    'Classical': [420, 280, 40, 0, 0, 0, 40, 220, 320, 420],
    'Dance': [520, 400, 120, 0, 180, 280, 400, 280, 180, 80],
    'Electronic': [520, 400, 0, -180, 180, 380, 180, 0, 380, 520],
  };

  // Equalizer
  bool eqEnabled = false;
  List<int> eqBands = List<int>.filled(10, 0);
  String eqPreset = 'Flat';
  bool bassBoostOn = false;
  int bassBoost = 0;
  bool surroundOn = false;
  int surround = 0;
  double audioBalanceLeft = 1;
  double audioBalanceRight = 1;

  Map<String, double> resumeMap = {};
  Map<String, double> speedMap = {};
  Set<String> bookmarks = {};
  Set<String> pinned = {};

  Color get seed => Color(seedColor);

  List<String> get visibleTabs {
    final vis = tabIds.where((t) => !hiddenTabs.contains(t)).toList();
    return vis.isEmpty ? ['videos'] : vis;
  }

  bool hideTab(String id, bool hide) {
    if (!tabIds.contains(id)) return false;
    if (hide) {
      final remaining = tabIds.where((t) => t != id && !hiddenTabs.contains(t)).length;
      if (remaining < 1) return false;
      if (!hiddenTabs.contains(id)) hiddenTabs = [...hiddenTabs, id];
    } else {
      hiddenTabs = hiddenTabs.where((t) => t != id).toList();
    }
    return true;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeModePref.values[(p.getInt('themeMode') ?? 0).clamp(0, ThemeModePref.values.length - 1)];
    seedColor = p.getInt('seedColor') ?? 0xFF38618D;
    dynamicColor = p.getBool('dynamicColor') ?? false;
    playlistStyle = PlaylistUiStyle.values[(p.getInt('playlistStyle') ?? 0).clamp(0, PlaylistUiStyle.values.length - 1)];
    rememberPlayback = p.getBool('rememberPlayback') ?? true;
    confirmDelete = p.getBool('confirmDelete') ?? true;
    scanOnStart = p.getBool('scanOnStart') ?? true;
    if (p.getBool('autoRefreshOnV1') != true) {
      autoRefresh = true;
      await p.setBool('autoRefresh', true);
      await p.setBool('autoRefreshOnV1', true);
    } else {
      autoRefresh = p.getBool('autoRefresh') ?? true;
    }
    showHiddenFolders = p.getBool('showHiddenFolders') ?? false;
    skipNomedia = p.getBool('skipNomedia') ?? true;
    showRemaining = p.getBool('showRemaining') ?? true;
    showClock = p.getBool('showClock') ?? true;
    showBattery = p.getBool('showBattery') ?? true;
    showSeekPreview = p.getBool('showSeekPreview') ?? true;
    if (p.getBool('rotationNoneV3') != true) {
      rotation = RotationLock.none;
      await p.setInt('rotation', RotationLock.none.index);
      await p.setBool('rotationNoneV3', true);
    } else {
      rotation = RotationLock.values[(p.getInt('rotation') ?? RotationLock.none.index).clamp(0, RotationLock.values.length - 1)];
    }
    decoder = DecoderMode.values[(p.getInt('decoder') ?? 1).clamp(0, DecoderMode.values.length - 1)];
    hwPriority = p.getBool('hwPriority') ?? true;
    seekStepSeconds = p.getInt('seekStepSeconds') ?? 10;
    autoMiniplayer = p.getBool('autoMiniplayer') ?? false;
    inAppMiniplayer = p.getBool('inAppMiniplayer') ?? true;
    if (p.getBool('pipDefaultOffV2') != true) {
      autoMiniplayer = false;
      await p.setBool('autoMiniplayer', false);
      await p.setBool('pipDefaultOffV2', true);
    }
    rememberBackgroundPlay = p.getBool('rememberBackgroundPlay') ?? false;
    backgroundPlay = p.getBool('backgroundPlay') ?? false;
    rememberAspect = p.getBool('rememberAspect') ?? true;
    aspect = AspectMode.values[(p.getInt('aspect') ?? 0).clamp(0, AspectMode.values.length - 1)];
    resumePlayback = p.getBool('resumePlayback') ?? true;
    rememberSpeed = p.getBool('rememberSpeed') ?? false;
    speed = p.getDouble('speed') ?? 1;
    rememberBrightness = p.getBool('rememberBrightness') ?? false;
    brightness = p.getDouble('brightness') ?? -1;
    longPress2x = p.getBool('longPress2x') ?? true;
    longPressVibration = p.getBool('longPressVibration') ?? true;
    doubleTapSeek = p.getBool('doubleTapSeek') ?? true;
    autoPlayNext = p.getBool('autoPlayNext') ?? true;
    gestureControl = p.getBool('gestureControl') ?? true;
    allowZoom = p.getBool('allowZoom') ?? true;
    rememberHdr = p.getBool('rememberHdr') ?? false;
    hdrOn = p.getBool('hdrOn') ?? true;
    pitchShift = p.getBool('pitchShift') ?? false;
    playMode = PlayMode.values[(p.getInt('playMode') ?? 0).clamp(0, PlayMode.values.length - 1)];
    highContrast = p.getBool('highContrast') ?? false;
    reduceMotion = p.getBool('reduceMotion') ?? false;
    largeControls = p.getBool('largeControls') ?? false;
    colorBlindDeuteranopia = p.getBool('cbD') ?? false;
    colorBlindProtanopia = p.getBool('cbP') ?? false;
    colorBlindTritanopia = p.getBool('cbT') ?? false;
    grayscale = p.getBool('grayscale') ?? false;
    invertColors = p.getBool('invertColors') ?? false;
    nightMode = p.getBool('nightMode') ?? false;
    nightWarmth = p.getDouble('nightWarmth') ?? 0.35;
    extraDim = p.getBool('extraDim') ?? false;
    boldText = p.getBool('boldText') ?? false;
    uiScale = p.getDouble('uiScale') ?? 1;
    contrast = p.getDouble('contrast') ?? 1;
    saturation = p.getDouble('saturation') ?? 1;
    gamma = p.getDouble('gamma') ?? 1;
    hueRotate = p.getDouble('hueRotate') ?? 0;
    mirror = p.getBool('mirror') ?? false;
    colorCorrection = p.getBool('colorCorrection') ?? false;
    alwaysHideNavBar = p.getBool('alwaysHideNavBar') ?? false;
    developerEnabled = p.getBool('developerEnabled') ?? false;
    debugLog = p.getBool('debugLog') ?? false;
    videoLogOverlay = p.getBool('videoLogOverlay') ?? false;
    videoLogShowState = p.getBool('videoLogShowState') ?? true;
    videoLogShowMedia = p.getBool('videoLogShowMedia') ?? true;
    videoLogShowRender = p.getBool('videoLogShowRender') ?? true;
    videoLogShowDecoder = p.getBool('videoLogShowDecoder') ?? true;
    videoLogShowTiming = p.getBool('videoLogShowTiming') ?? false;
    logPlayerEvents = p.getBool('logPlayerEvents') ?? false;
    logGestureEvents = p.getBool('logGestureEvents') ?? false;
    logLifecycleEvents = p.getBool('logLifecycleEvents') ?? false;
    hiddenTabs = List<String>.from(p.getStringList('hiddenTabs') ?? const []);
    hiddenTabs.removeWhere((t) => !tabIds.contains(t));
    if (hiddenTabs.length >= tabIds.length) {
      hiddenTabs = hiddenTabs.take(tabIds.length - 1).toList();
    }

    quickActions = List<String>.from(p.getStringList('quickActions') ?? defaultQuickActions);
    quickActions.removeWhere((id) => !allQuickActions.containsKey(id));
    if (quickActions.isEmpty) quickActions = List<String>.from(defaultQuickActions);

    if (p.getBool('playerTitleV3') != true) {
      titleActions = List<String>.from(defaultTitleActions);
      await p.setStringList('titleActions', titleActions);
      await p.setBool('playerTitleV3', true);
    } else {
      titleActions = List<String>.from(p.getStringList('titleActions') ?? defaultTitleActions);
      if (titleActions.isEmpty) titleActions = List<String>.from(defaultTitleActions);
    }
    titleActions.removeWhere((id) => id == 'subtitle');
    hudFabsJson = p.getString('hudFabsJson') ?? '[]';

    eqEnabled = p.getBool('eqEnabled') ?? false;
    eqPreset = p.getString('eqPreset') ?? 'Flat';
    bassBoostOn = p.getBool('bassBoostOn') ?? false;
    bassBoost = (p.getInt('bassBoost') ?? 0).clamp(0, 1000).toInt();
    surroundOn = p.getBool('surroundOn') ?? false;
    surround = (p.getInt('surround') ?? 0).clamp(0, 1000).toInt();
    audioBalanceLeft = (p.getDouble('audioBalanceLeft') ?? 1).clamp(0.0, 1.0).toDouble();
    audioBalanceRight = (p.getDouble('audioBalanceRight') ?? 1).clamp(0.0, 1.0).toDouble();
    final bandsRaw = p.getString('eqBands');
    if (bandsRaw != null) {
      try {
        eqBands = (jsonDecode(bandsRaw) as List).map((e) => (e as num).toInt()).toList();
      } catch (_) {}
    }
    while (eqBands.length < 10) {
      eqBands.add(0);
    }
    if (eqBands.length > 10) eqBands = eqBands.take(10).toList();

    final resume = p.getString('resumeMap');
    if (resume != null) {
      try {
        resumeMap = (jsonDecode(resume) as Map).map((k, v) => MapEntry('$k', (v as num).toDouble()));
      } catch (_) {}
    }
    final speeds = p.getString('speedMap');
    if (speeds != null) {
      try {
        speedMap = (jsonDecode(speeds) as Map).map((k, v) => MapEntry('$k', (v as num).toDouble()));
      } catch (_) {}
    }
    bookmarks = (p.getStringList('bookmarks') ?? []).toSet();
    pinned = (p.getStringList('pinned') ?? []).toSet();
  }

  Future<void>? _saving;
  bool _saveAgain = false;

  Future<void> save() {
    if (_saving != null) {
      _saveAgain = true;
      return _saving!;
    }
    final run = () async {
      try {
        do {
          _saveAgain = false;
          await _saveNow();
        } while (_saveAgain);
      } catch (_) {
      } finally {
        _saving = null;
      }
    }();
    _saving = run;
    return run;
  }

  Future<void> saveResume() async {
    try {
      if (resumeMap.length > 1500) {
        final keys = resumeMap.keys.toList();
        for (final k in keys.take(resumeMap.length - 1000)) {
          resumeMap.remove(k);
        }
      }
      final p = await SharedPreferences.getInstance();
      await p.setString('resumeMap', jsonEncode(resumeMap));
    } catch (_) {}
  }

  Future<void> _saveNow() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', themeMode.index);
    await p.setInt('seedColor', seedColor);
    await p.setBool('dynamicColor', dynamicColor);
    await p.setInt('playlistStyle', playlistStyle.index);
    await p.setBool('rememberPlayback', rememberPlayback);
    await p.setBool('confirmDelete', confirmDelete);
    await p.setBool('scanOnStart', scanOnStart);
    await p.setBool('autoRefresh', autoRefresh);
    await p.setBool('showHiddenFolders', showHiddenFolders);
    await p.setBool('skipNomedia', skipNomedia);
    await p.setBool('showRemaining', showRemaining);
    await p.setBool('showClock', showClock);
    await p.setBool('showBattery', showBattery);
    await p.setBool('showSeekPreview', showSeekPreview);
    await p.setInt('rotation', rotation.index);
    await p.setInt('decoder', decoder.index);
    await p.setBool('hwPriority', hwPriority);
    await p.setInt('seekStepSeconds', seekStepSeconds);
    await p.setBool('autoMiniplayer', autoMiniplayer);
    await p.setBool('inAppMiniplayer', inAppMiniplayer);
    await p.setBool('rememberBackgroundPlay', rememberBackgroundPlay);
    await p.setBool('backgroundPlay', backgroundPlay);
    await p.setBool('rememberAspect', rememberAspect);
    await p.setInt('aspect', aspect.index);
    await p.setBool('resumePlayback', resumePlayback);
    await p.setBool('rememberSpeed', rememberSpeed);
    await p.setDouble('speed', speed);
    await p.setBool('rememberBrightness', rememberBrightness);
    await p.setDouble('brightness', brightness);
    await p.setBool('longPress2x', longPress2x);
    await p.setBool('longPressVibration', longPressVibration);
    await p.setBool('doubleTapSeek', doubleTapSeek);
    await p.setBool('autoPlayNext', autoPlayNext);
    await p.setBool('gestureControl', gestureControl);
    await p.setBool('allowZoom', allowZoom);
    await p.setBool('rememberHdr', rememberHdr);
    await p.setBool('hdrOn', hdrOn);
    await p.setBool('pitchShift', pitchShift);
    await p.setInt('playMode', playMode.index);
    await p.setBool('highContrast', highContrast);
    await p.setBool('reduceMotion', reduceMotion);
    await p.setBool('largeControls', largeControls);
    await p.setBool('cbD', colorBlindDeuteranopia);
    await p.setBool('cbP', colorBlindProtanopia);
    await p.setBool('cbT', colorBlindTritanopia);
    await p.setBool('grayscale', grayscale);
    await p.setBool('invertColors', invertColors);
    await p.setBool('nightMode', nightMode);
    await p.setDouble('nightWarmth', nightWarmth);
    await p.setBool('extraDim', extraDim);
    await p.setBool('boldText', boldText);
    await p.setDouble('uiScale', uiScale);
    await p.setDouble('contrast', contrast);
    await p.setDouble('saturation', saturation);
    await p.setDouble('gamma', gamma);
    await p.setDouble('hueRotate', hueRotate);
    await p.setBool('mirror', mirror);
    await p.setBool('colorCorrection', colorCorrection);
    await p.setBool('alwaysHideNavBar', alwaysHideNavBar);
    await p.setBool('developerEnabled', developerEnabled);
    await p.setBool('debugLog', debugLog);
    await p.setBool('videoLogOverlay', videoLogOverlay);
    await p.setBool('videoLogShowState', videoLogShowState);
    await p.setBool('videoLogShowMedia', videoLogShowMedia);
    await p.setBool('videoLogShowRender', videoLogShowRender);
    await p.setBool('videoLogShowDecoder', videoLogShowDecoder);
    await p.setBool('videoLogShowTiming', videoLogShowTiming);
    await p.setBool('logPlayerEvents', logPlayerEvents);
    await p.setBool('logGestureEvents', logGestureEvents);
    await p.setBool('logLifecycleEvents', logLifecycleEvents);
    await p.setStringList('hiddenTabs', hiddenTabs);
    await p.setStringList('quickActions', quickActions);
    await p.setStringList('titleActions', titleActions);
    await p.setString('hudFabsJson', hudFabsJson);
    await p.setBool('eqEnabled', eqEnabled);
    await p.setString('eqPreset', eqPreset);
    await p.setString('eqBands', jsonEncode(eqBands));
    await p.setBool('bassBoostOn', bassBoostOn);
    await p.setInt('bassBoost', bassBoost);
    await p.setBool('surroundOn', surroundOn);
    await p.setInt('surround', surround);
    await p.setDouble('audioBalanceLeft', audioBalanceLeft);
    await p.setDouble('audioBalanceRight', audioBalanceRight);
    await p.setString('resumeMap', jsonEncode(resumeMap));
    await p.setString('speedMap', jsonEncode(speedMap));
    await p.setStringList('bookmarks', bookmarks.toList());
    await p.setStringList('pinned', pinned.toList());
  }

  void applyPreset(String name) {
    final bands = eqPresets[name];
    if (bands == null) return;
    eqPreset = name;
    eqBands = List<int>.from(bands);
  }
}
