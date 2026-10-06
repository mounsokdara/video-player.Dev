part of 'player.dart';

extension PlayerSheets on _PlayerPageState {
  Future<void> _playlist() async {
    if (appSettings.playlistStyle == PlaylistUiStyle.youtube) return;
    await _sheetPlaylist();
  }

  Future<void> _sheetPlaylist() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        final pad = SystemBars.rawOf(context);
        final insets = MediaQuery.viewInsetsOf(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, sc) {
            return Padding(
              padding: EdgeInsets.only(bottom: pad.bottom + insets.bottom),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ChipScroller(
                      children: [
                        for (final m in PlayMode.values)
                          ChoiceChip(
                            label: Text(_playModeLabel(m)),
                            selected: appSettings.playMode == m,
                            onSelected: (_) {
                              setState(() => appSettings.playMode = m);
                              appSettings.save();
                              Navigator.pop(ctx);
                            },
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: sc,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final v = list[i];
                        return ListTile(
                          selected: i == index,
                          leading: SizedBox(width: 64, height: 40, child: VideoThumb(item: v, radius: 6)),
                          title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatDuration(v.duration)),
                          onTap: () {
                            Navigator.pop(ctx);
                            index = i;
                            _openCurrent();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _playModeLabel(PlayMode m) => switch (m) {
        PlayMode.order => 'Order',
        PlayMode.loopAll => 'Loop all',
        PlayMode.repeatOne => 'Repeat current',
        PlayMode.shuffle => 'Shuffle all',
        PlayMode.noAutoplay => 'No autoplay',
      };


  IconData _actionIcon(String id) => switch (id) {
        'speed' => Icons.speed,
        'background' => Icons.headphones_outlined,
        'screenshot' => Icons.camera_alt_outlined,
        'lock' => Icons.lock_outline,
        'aspect' => Icons.aspect_ratio,
        'ab' => Icons.repeat,
        'eq' => Icons.equalizer,
        'bookmark' => Icons.bookmark_outline,
        'pin' => Icons.push_pin_outlined,
        'brightness' => Icons.brightness_6_outlined,
        'rotate' => Icons.screen_rotation,
        'share' => Icons.share_outlined,
        'night' => Icons.nights_stay_outlined,
        'zoom' => Icons.zoom_in,
        'skipBack' => Icons.replay_10,
        'skipForward' => Icons.forward_10,
        'popup' => Icons.picture_in_picture_alt,
        'hdr' => Icons.hdr_on,
        'playlist' => Icons.queue_music,
        'more' => Icons.more_vert,
        'color' => Icons.color_lens_outlined,
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
        _ => Icons.tune,
      };

  Future<void> _simple(String t, String b) async {
    if (!mounted) return;
    await SystemBars.modal(() => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(title: Text(t), content: Text(b), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]),
    ));
  }

  Future<void> _speedSheet() async {
    double local = speed;
    var custom = false;
    final box = TextEditingController(text: speed.toStringAsFixed(2));
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        final pad = SystemBars.rawOf(context);
        return StatefulBuilder(builder: (ctx, ss) {
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + insets.bottom + pad.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Speed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Slider(
                    min: 0.25,
                    max: 4,
                    value: local.clamp(0.25, 4).toDouble(),
                    onChanged: (v) {
                      ss(() {
                        custom = false;
                        local = v;
                        box.text = v.toStringAsFixed(2);
                      });
                    }),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: box,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: custom ? 'Custom speed' : 'Speed value',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (t) {
                          final n = double.tryParse(t);
                          if (n != null) {
                            ss(() {
                              custom = true;
                              local = n.clamp(0.25, 8).toDouble();
                            });
                          }
                        },
                        onSubmitted: (t) {
                          final n = double.tryParse(t);
                          if (n != null) {
                            ss(() {
                              custom = true;
                              local = n.clamp(0.25, 8).toDouble();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: const Text('Pitch shift'),
                      selected: appSettings.pitchShift,
                      onSelected: (v) async {
                        ss(() => appSettings.pitchShift = v);
                        await appSettings.save();
                        await _applySpeed();
                      },
                    ),
                  ],
                ),
                if (custom)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Using typed custom speed', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final typed = double.tryParse(box.text);
                    speed = (custom && typed != null) ? typed.clamp(0.25, 8).toDouble() : local;
                    appSettings.speed = speed;
                    await _applySpeed();
                    await appSettings.save();
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _zoomSheet() async {
    var local = (_zoomScale * 100).clamp(1, 1000).toDouble();
    final box = TextEditingController(text: local.round().toString());
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        final pad = SystemBars.rawOf(context);
        return StatefulBuilder(builder: (ctx, ss) {
          void apply(double pct) {
            local = pct.clamp(1, 1000).toDouble();
            box.text = local.round().toString();
            setState(() {
              _zoomScale = local / 100;
              if (_zoomScale <= 1.001) _zoomPan = Offset.zero;
              _showZoomHud = true;
            });
            _zoomHudTimer?.cancel();
            _zoomHudTimer = Timer(const Duration(milliseconds: 900), () {
              if (mounted) setState(() => _showZoomHud = false);
            });
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + insets.bottom + pad.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Zoom', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Slider(
                  min: 1,
                  max: 1000,
                  value: local.toDouble(),
                  onChanged: (v) => ss(() => apply(v)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: box,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Percent',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (t) {
                          final n = double.tryParse(t);
                          if (n != null) ss(() => apply(n));
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => ss(() => apply(100)),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
    box.dispose();
  }

  Future<void> _brightnessSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        return SafeArea(
          child: StatefulBuilder(builder: (ctx, ss) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + insets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Brightness', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      const Icon(Icons.brightness_low),
                      Expanded(
                        child: Slider(
                          value: brightness,
                          onChanged: (v) async {
                            ss(() => brightness = v);
                            try {
                              await ScreenBrightness().setApplicationScreenBrightness(v);
                            } catch (_) {}
                            if (appSettings.rememberBrightness) {
                              appSettings.brightness = v;
                            }
                          },
                          onChangeEnd: (_) => appSettings.save(),
                        ),
                      ),
                      Text('${(brightness * 100).round()}%'),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        try {
                          await ScreenBrightness().resetApplicationScreenBrightness();
                          final sys = await ScreenBrightness().system;
                          ss(() => brightness = sys);
                          _systemBrightness = sys;
                        } catch (_) {
                          final reset = _systemBrightness ?? 0.5;
                          ss(() => brightness = reset);
                        }
                        appSettings.brightness = -1;
                        await appSettings.save();
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _aspectSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        Widget item(AspectMode m, String t) => RadioListTile<AspectMode>(
              value: m,
              groupValue: aspect,
              title: Text(t),
              onChanged: (v) {
                setState(() => aspect = v!);
                if (appSettings.rememberAspect) {
                  appSettings.aspect = v!;
                  appSettings.save();
                }
                Navigator.pop(ctx);
              },
            );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Screen mode', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
              item(AspectMode.fit, 'Fit'),
              item(AspectMode.zoom, 'Zoomed full screen'),
              item(AspectMode.original, 'Original size'),
              item(AspectMode.stretch, 'Stretch'),
              item(AspectMode.ratio16_9, '16:9'),
              item(AspectMode.ratio4_3, '4:3'),
              item(AspectMode.ratio21_9, '21:9'),
              item(AspectMode.ratio2_35, '2.35:1'),
              item(AspectMode.ratio1_1, '1:1'),
              item(AspectMode.ratio9_16, '9:16'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rotationSheet() async {
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
    await showAppSheet<void>(
      context: context,
      initial: 0.62,
      children: (ctx) => [
        const ListTile(title: Text('Rotation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
        for (final e in modes)
          RadioListTile<RotationLock>(
            value: e,
            groupValue: appSettings.rotation,
            title: Text(e.label),
            onChanged: (v) {
              appSettings.rotation = v!;
              appSettings.save();
              _applyRotation();
              Navigator.pop(ctx);
            },
          ),
      ],
    );
  }

  Future<void> _colorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        return SafeArea(
          child: StatefulBuilder(builder: (ctx, ss) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + insets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Color correction', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable'),
                    value: appSettings.colorCorrection,
                    onChanged: (v) => ss(() => appSettings.colorCorrection = v),
                  ),
                  _sl('Contrast', appSettings.contrast, 0.4, 2, (v) => ss(() => appSettings.contrast = v)),
                  _sl('Saturation', appSettings.saturation, 0, 2, (v) => ss(() => appSettings.saturation = v)),
                  _sl('Gamma', appSettings.gamma, 0.4, 2.2, (v) => ss(() => appSettings.gamma = v)),
                  _sl('Hue', appSettings.hueRotate, -180, 180, (v) => ss(() => appSettings.hueRotate = v)),
                  FilledButton(
                    onPressed: () {
                      appSettings.save();
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  Widget _sl(String t, double v, double a, double b, ValueChanged<double> on) {
    return Row(children: [
      SizedBox(width: 92, child: Text(t)),
      Expanded(child: Slider(min: a, max: b, value: v.clamp(a, b).toDouble(), onChanged: on)),
    ]);
  }

  Future<void> _volumeSheet() async {
    var vol = volume;
    try {
      vol = await VolumeController.instance.getVolume();
      volume = vol;
    } catch (_) {}
    var left = appSettings.audioBalanceLeft.clamp(0.0, 1.0).toDouble();
    var right = appSettings.audioBalanceRight.clamp(0.0, 1.0).toDouble();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        final pad = SystemBars.rawOf(context);
        return SafeArea(
          child: StatefulBuilder(builder: (ctx, ss) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + insets.bottom + pad.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Volume', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      const Icon(Icons.volume_down),
                      Expanded(
                        child: Slider(
                          value: vol.clamp(0.0, 1.0).toDouble(),
                          onChanged: (v) {
                            ss(() {
                              vol = v;
                              volume = v;
                            });
                            try {
                              VolumeController.instance.setVolume(v);
                            } catch (_) {}
                          },
                        ),
                      ),
                      SizedBox(width: 40, child: Text('${(vol * 100).round()}%')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Audio Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 52, child: Text('Left')),
                      Expanded(
                        child: Slider(
                          value: left,
                          onChanged: (v) {
                            ss(() => left = v);
                            appSettings.audioBalanceLeft = v;
                            unawaited(AndroidBridge.setStereoVolume(left, right));
                          },
                          onChangeEnd: (_) => appSettings.save(),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('${(left * 100).round()}%')),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 52, child: Text('Right')),
                      Expanded(
                        child: Slider(
                          value: right,
                          onChanged: (v) {
                            ss(() => right = v);
                            appSettings.audioBalanceRight = v;
                            unawaited(AndroidBridge.setStereoVolume(left, right));
                          },
                          onChangeEnd: (_) => appSettings.save(),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('${(right * 100).round()}%')),
                    ],
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _timerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in [15, 30, 45, 60, 90])
                ListTile(
                  title: Text('Stop in $m min'),
                  onTap: () {
                    PlaybackSession.armSleep(Duration(minutes: m));
                    Navigator.pop(ctx);
                    _flash('Timer $m min');
                  },
                ),
              ListTile(
                title: const Text('Cancel timer'),
                onTap: () {
                  PlaybackSession.cancelSleep();
                  Navigator.pop(ctx);
                  _flash('Timer off');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Auto play next'),
                value: appSettings.autoPlayNext,
                onChanged: (v) {
                  setState(() => appSettings.autoPlayNext = v);
                  appSettings.save();
                  Navigator.pop(ctx);
                },
              ),
              SwitchListTile(
                title: const Text('Resume from last position'),
                value: appSettings.resumePlayback,
                onChanged: (v) {
                  setState(() => appSettings.resumePlayback = v);
                  appSettings.save();
                  Navigator.pop(ctx);
                },
              ),
              SwitchListTile(
                title: const Text('Background play'),
                value: appSettings.backgroundPlay,
                onChanged: (v) {
                  _toggleBackground(v);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _screenshot() {
    final path = item.path;
    final pos = vc?.value.position.inMilliseconds ?? 0;
    unawaited(() async {
      final saved = await AndroidBridge.screenshotWindow(title: item.title, path: path, positionMs: pos);
      if (!mounted) return;
      if (saved != null) {
        _flash('Saved to DCIM/Screenshots');
        unawaited(AndroidBridge.toast('Saved to DCIM/Screenshots'));
      } else {
        _flash('Could not capture frame');
      }
    }());
    _flash('Saving');
  }
}
