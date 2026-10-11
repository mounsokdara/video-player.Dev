import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:video_player_app/accessibility/live_caption/live_caption_controller.dart';

/// Adapts any [Listenable] playback source (such as the playback engine) to the millisecond
/// position the overlay needs.
class EnginePositionListenable implements ValueListenable<int> {
  EnginePositionListenable(this._source, this._read);
  final Listenable _source;
  final int Function() _read;

  @override
  int get value => _read();

  @override
  void addListener(VoidCallback listener) => _source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _source.removeListener(listener);
}

/// Caption text plus extraction progress for the video being played. It only draws: the captions
/// themselves live in [LiveCaptionController], so rebuilding or moving this widget never loses them.
/// Put it inside an IgnorePointer at the bottom of the video.
class LiveCaptionOverlay extends StatefulWidget {
  const LiveCaptionOverlay({super.key, required this.path, required this.position, this.compact = false});

  final String path;

  /// Playback position in milliseconds.
  final ValueListenable<int> position;

  /// Smaller text for the mini player.
  final bool compact;

  @override
  State<LiveCaptionOverlay> createState() => _LiveCaptionOverlayState();
}

class _LiveCaptionOverlayState extends State<LiveCaptionOverlay> {
  final LiveCaptionController _ctl = LiveCaptionController.instance;

  @override
  void initState() {
    super.initState();
    _ctl.attach(this, widget.path, widget.position);
  }

  @override
  void didUpdateWidget(LiveCaptionOverlay old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.position != widget.position) {
      _ctl.attach(this, widget.path, widget.position);
    }
  }

  @override
  void dispose() {
    _ctl.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return AnimatedBuilder(
      animation: Listenable.merge([_ctl, widget.position]),
      builder: (context, _) {
        final text = _ctl.textAt(widget.position.value);
        final chip = _ctl.chipText;
        final p = _ctl.chipProgress;
        if (text.isEmpty && chip == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chip != null)
              Container(
                margin: EdgeInsets.only(bottom: text.isEmpty ? 0 : 4),
                padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(compact ? 6 : 10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chip,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: compact ? 9 : 12),
                    ),
                    if (p != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: SizedBox(
                          width: compact ? 70 : 140,
                          height: 3,
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            color: const Color(0xFF9E8CFF),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (text.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12, vertical: compact ? 2 : 6),
                decoration: BoxDecoration(
                  color: const Color(0xB8000000),
                  borderRadius: BorderRadius.circular(compact ? 6 : 8),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 11 : 18,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
