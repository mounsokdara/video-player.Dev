import 'package:flutter/material.dart';

import 'package:video_player_app/playback/engine.dart';
import 'package:video_player_app/playback/render_profile.dart';

Future<void> showRenderSheet(BuildContext context, PlaybackEngine? engine) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
    builder: (_) => _RenderSheet(engine: engine),
  );
}

class _RenderSheet extends StatefulWidget {
  const _RenderSheet({required this.engine});
  final PlaybackEngine? engine;

  @override
  State<_RenderSheet> createState() => _RenderSheetState();
}

class _RenderSheetState extends State<_RenderSheet> {
  final _rs = RenderSettings.instance;
  late bool _sdr;

  PlaybackEngine? get _e => widget.engine;

  @override
  void initState() {
    super.initState();
    _sdr = _e?.sdrMode ?? false;
  }

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final active = e != null && e.hasPlayer;
    final tune = _rs.tuning(sdr: _sdr);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Render settings', style: Theme.of(context).textTheme.titleLarge),

              _title('HDR / SDR'),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('HDR')),
                  ButtonSegment<bool>(value: true, label: Text('SDR')),
                ],
                selected: {_sdr},
                onSelectionChanged: active
                    ? (s) {
                        setState(() => _sdr = s.first);
                        e?.setSdrMode(_sdr);
                      }
                    : null,
              ),
              _hint(active
                  ? 'Switches the active render mode live. For HDR videos this changes HDR/SDR tone mapping; for SDR videos it applies the selected render tuning.'
                  : 'Start a video to change the render mode.'),
              _title('${_sdr ? 'SDR' : 'HDR'} brightness'),
              Text('White level: ${tune.peak} nits (higher = darker)'),
              Slider(
                value: tune.peak.toDouble().clamp(100.0, 1000.0).toDouble(),
                min: 100,
                max: 1000,
                divisions: 36,
                onChanged: (v) {
                  setState(() => _rs.setTuning(sdr: _sdr, peak: v.round()));
                  e?.retune();
                },
                onChangeEnd: (_) => _rs.save(),
              ),
              Text('Mid-tones: ${tune.gamma} (negative = darker)'),
              Slider(
                value: tune.gamma.toDouble().clamp(-50.0, 50.0).toDouble(),
                min: -50,
                max: 50,
                divisions: 100,
                onChanged: (v) {
                  setState(() => _rs.setTuning(sdr: _sdr, gamma: v.round()));
                  e?.retune();
                },
                onChangeEnd: (_) => _rs.save(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() => _rs.resetTuning(sdr: _sdr));
                    _rs.save();
                    e?.retune();
                  },
                  child: const Text('Reset brightness'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
