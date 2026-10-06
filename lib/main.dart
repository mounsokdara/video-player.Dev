import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:video_player_app/core/crash.dart';
import 'package:video_player_app/library/home.dart';
import 'package:video_player_app/library/picker.dart';
import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/library/library.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/settings/settings.dart';
import 'package:video_player_app/settings/settings_ui.dart';
import 'package:video_player_app/core/theme.dart';
import 'package:video_player_app/core/theme_export.dart';

export 'package:video_player_app/settings/settings.dart';

final library = LibraryService(appSettings);

int? _lastWindowBg;

/// Remembers the app surface color so native activities (Settings) can paint
/// their window with it before Flutter draws, instead of flashing black.
void _rememberWindowBg(int argb) {
  if (_lastWindowBg == argb) return;
  _lastWindowBg = argb;
  SharedPreferences.getInstance().then((p) => p.setInt('windowBgArgb', argb)).catchError((_) => false);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await runZonedGuarded(() async {
    FlutterError.onError = (details) {
      CrashLog.record('FLUTTER', details.exceptionAsString(), details.stack);
      FlutterError.presentError(details);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      CrashLog.record('PLATFORM', '$error', stack);
      return true;
    };
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await appSettings.load();
    await CrashLog.install();
    runApp(const VideoPlayerApp());
  }, (error, stack) {
    CrashLog.record('ZONE', '$error', stack);
  });
}

class VideoPlayerApp extends StatefulWidget {
  const VideoPlayerApp({super.key});

  @override
  State<VideoPlayerApp> createState() => _VideoPlayerAppState();
}

class _VideoPlayerAppState extends State<VideoPlayerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SharedPreferences.getInstance().then((p) => p.reload()).then((_) => appSettings.load()).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _settingsChanged() {
    setState(() {});
    appSettings.save();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (light, dark) {
        final mode = appSettings.themeMode;
        final lightTheme = AppTheme.build(brightness: Brightness.light, settings: appSettings, dynamicScheme: light);
        final darkTheme = AppTheme.build(brightness: Brightness.dark, settings: appSettings, dynamicScheme: dark);
        ThemeExport.publish(lightTheme.colorScheme, darkTheme.colorScheme);
        return MaterialApp(
          navigatorKey: appNavigator,
          navigatorObservers: [SystemBarObserver()],
          title: 'Video Player',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: switch (mode) {
            ThemeModePref.system => ThemeMode.system,
            ThemeModePref.light => ThemeMode.light,
            ThemeModePref.dark => ThemeMode.dark,
          },
          builder: (context, child) {
            _rememberWindowBg(Theme.of(context).colorScheme.surface.toARGB32());
            final scale = appSettings.uiScale.clamp(0.85, 1.35).toDouble();
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                boldText: appSettings.boldText,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          initialRoute: WidgetsBinding.instance.platformDispatcher.defaultRouteName,
          onGenerateInitialRoutes: (name) {
            if (name == '/pick' || name.endsWith('/pick')) {
              return [
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/pick'),
                  builder: (_) => const VideoPickerPage(),
                ),
              ];
            }
            if (name == '/settings' || name.endsWith('/settings')) {
              return [
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/settings'),
                  builder: (_) => SettingsHost(onChanged: _settingsChanged),
                ),
              ];
            }
            return [
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/'),
                builder: (_) => HomeShell(
                  onSettingsChanged: () {
                    setState(() {});
                    appSettings.save();
                  },
                ),
              ),
            ];
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/pick') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const VideoPickerPage(),
              );
            }
            if (settings.name == '/settings') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => SettingsHost(onChanged: _settingsChanged),
              );
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => HomeShell(
                onSettingsChanged: () {
                  setState(() {});
                  appSettings.save();
                },
              ),
            );
          },
          onUnknownRoute: (settings) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
