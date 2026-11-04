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
    // Re-read tune AFTER _sdr is current so sliders always reflect the right profile.
    final tune = _rs.tuning(sdr: _sdr);
    // Show HDR toggle only when the source actually needs HDR tone-mapping.
    // For SDR videos _convert is false, so we lock the selector and show SDR tuning.
    final sourceIsHdr = e?.hdrActive ?? false;

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
                // Only allow switching when active AND the source is an HDR video.
                // SDR videos always use the SDR tuning profile; showing the toggle
                // for them was what caused HDR settings to overwrite SDR ones.
                onSelectionChanged: (active && sourceIsHdr)
                    ? (s) {
                        final newSdr = s.first;
                        setState(() => _sdr = newSdr);
                        e?.setSdrMode(newSdr);
                      }
                    : null,
              ),
              _hint(active
                  ? (sourceIsHdr
                      ? 'Switches HDR↔SDR tone mapping live for this HDR video.'
                      : 'This video is SDR — brightness controls apply the SDR tuning profile.')
                  : 'Start a video to change the render mode.'),
              // The title and all sliders below always use the _sdr-keyed profile,
              // so editing brightness for an SDR source writes to peakSdr/gammaSdr
              // and editing for an HDR source (HDR mode) writes to peakHdr/gammaHdr.
              _title('${_sdr ? 'SDR' : 'HDR'} brightness'),
              Text('White level: ${tune.peak} nits (higher = brighter)'),
              Slider(
                value: tune.peak.toDouble().clamp(100.0, 1000.0).toDouble(),
                min: 100,
                max: 1000,
                onChanged: (v) {
                  // Capture current _sdr to avoid a race if the toggle fires mid-drag.
                  final forSdr = _sdr;
                  setState(() => _rs.setTuning(sdr: forSdr, peak: v.round()));
                  e?.retune();
                },
                onChangeEnd: (_) => _rs.save(),
              ),
              Text('Mid-tones: ${tune.gamma} (negative = darker)'),
              Slider(
                value: tune.gamma.toDouble().clamp(-50.0, 50.0).toDouble(),
                min: -50,
                max: 50,
                onChanged: (v) {
                  final forSdr = _sdr;
                  setState(() => _rs.setTuning(sdr: forSdr, gamma: v.round()));
                  e?.retune();
                },
                onChangeEnd: (_) => _rs.save(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    final forSdr = _sdr;
                    setState(() => _rs.resetTuning(sdr: forSdr));
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
