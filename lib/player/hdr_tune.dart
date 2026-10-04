import 'package:flutter/material.dart';

import 'package:video_player_app/playback/engine.dart';

Future<void> showHdrTune(BuildContext context, PlaybackEngine? engine) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      var peak = PlaybackEngine.hdrPeak.toDouble();
      var gamma = PlaybackEngine.hdrGamma.toDouble();
      return StatefulBuilder(
        builder: (ctx, set) {
          Future<void> apply({bool save = false}) async {
            await engine?.setHdrTuning(peak: peak.round(), gamma: gamma.round(), save: save);
          }

          final active = engine?.hdrActive ?? false;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HDR brightness', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    active
                        ? 'Changes apply live to this video.'
                        : 'This video is not using the HDR path, so nothing will change until you play an HDR video.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text('White level: ${peak.round()} nits  (higher = darker)'),
                  Slider(
                    value: peak.clamp(100.0, 1000.0).toDouble(),
                    min: 100,
                    max: 1000,
                    divisions: 36,
                    onChanged: (v) {
                      set(() => peak = v);
                      apply();
                    },
                    onChangeEnd: (_) => apply(save: true),
                  ),
                  Text('Mid-tones: ${gamma.round()}  (negative = darker)'),
                  Slider(
                    value: gamma.clamp(-50.0, 50.0).toDouble(),
                    min: -50,
                    max: 50,
                    divisions: 100,
                    onChanged: (v) {
                      set(() => gamma = v);
                      apply();
                    },
                    onChangeEnd: (_) => apply(save: true),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        set(() {
                          peak = PlaybackEngine.hdrPeakDefault.toDouble();
                          gamma = 0;
                        });
                        apply(save: true);
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
