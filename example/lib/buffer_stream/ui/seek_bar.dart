import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// A draggable seek bar for SoLoud-backed audio.
/// - Reads duration/position using the same methods as BufferBar
/// - Calls [onSeek] with the desired absolute [Duration]
class SeekBar extends StatefulWidget {
  const SeekBar({
    required this.sound,
    required this.onSeek,
    required this.bufferingType,
    required this.handle,
    super.key,
    this.height = 28,
    this.trackRadius = 6,
    this.thumbRadius = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    this.scrubContinuously = false,
    this.labelBuilder,
    this.backgroundColor,
    this.bufferedColor,
    this.playedColor,
    this.thumbColor,
  });

  final SoundHandle? handle;
  final AudioSource? sound;
  final BufferingType bufferingType;
  final ValueChanged<Duration> onSeek;

  /// Visual tuning
  final double height;
  final double trackRadius;
  final double thumbRadius;
  final EdgeInsets padding;

  /// If true, calls onSeek on every drag update (DJ-style scrubbing).
  /// If false (default), calls onSeek on drag end/tap up.
  final bool scrubContinuously;

  /// Optional label builder to render e.g. current/total time above the bar.
  /// (pos, total) -> widget
  final Widget Function(Duration pos, Duration total)? labelBuilder;

  /// Optional colors (falls back to Theme)
  final Color? backgroundColor;
  final Color? bufferedColor;
  final Color? playedColor;
  final Color? thumbColor;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  Timer? _ticker;
  // Mirror your BufferBar’s “growing cap” approach for buffer bytes.
  int _currentMaxBytes = 1024 * 1024 * 10; // start at 10 MB like your default
  bool _dragging = false;
  double _dragFraction = 0; // 0..1 while dragging

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && !_dragging) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _total() {
    if (widget.sound == null) {
      return Duration.zero;
    }
    try {
      return SoLoud.instance.getLength(widget.sound!);
    } catch (_) {
      return Duration.zero;
    }
  }

  Duration _position() {
    if (widget.handle == null) {
      return Duration.zero;
    }
    try {
      if (widget.bufferingType == BufferingType.preserved) {
        // Use first handle position if available

        return SoLoud.instance.getPosition(widget.handle!);
      } else {
        // Streamed mode: consumed stream time
        return SoLoud.instance.getStreamTimeConsumed(widget.sound!);
      }
    } catch (_) {
      return Duration.zero;
    }
  }

  /// Returns 0..1 best-effort buffered fraction using the same idea
  /// as BufferBar (growing max bucket). This isn’t total-bytes-accurate,
  /// but gives a useful visual cue consistent with your BufferBar.
  double _bufferedFraction() {
    if (widget.sound == null) {
      return 0;
    }
    try {
      final size = SoLoud.instance.getBufferSize(widget.sound!);
      if (size >= _currentMaxBytes) {
        // grow window in 10 MB steps (like your startingMb=10 behavior)
        _currentMaxBytes += 1024 * 1024 * 10;
      }
      return _currentMaxBytes <= 0
          ? 0
          : (size / _currentMaxBytes).clamp(0.0, 1.0);
    } catch (_) {
      return 0;
    }
  }

  void _handleTapOrDrag(
    Offset localPos,
    double width,
    Duration total, {
    bool commit = true,
  }) {
    if (total.inMilliseconds <= 0) return;

    final dx = localPos.dx.clamp(0.0, width);
    final frac = width == 0 ? 0.0 : (dx / width);
    final seekTo = total * frac;

    setState(() {
      _dragFraction = frac;
    });
    print('seekTo: $seekTo');
    if (commit || widget.scrubContinuously) {
      widget.onSeek(seekTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sound == null || widget.handle == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final total = _total();
    final pos = _position();
    final playedFrac = total.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final bufferedFrac = _bufferedFraction();

    final bg = widget.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withOpacity(0.7);
    final buf =
        widget.bufferedColor ?? theme.colorScheme.primary.withOpacity(0.25);
    final played = widget.playedColor ?? theme.colorScheme.primary;
    final thumb = widget.thumbColor ?? theme.colorScheme.primary;

    final label = widget.labelBuilder?.call(pos, total);

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: label),
          LayoutBuilder(
            builder: (context, constraints) {
              const width = 300.0;
              final trackHeight = widget.height;

              // Use preview fraction while dragging, otherwise live playedFrac
              final effectivePlayedFrac =
                  _dragging ? _dragFraction : playedFrac;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _handleTapOrDrag(
                    d.localPosition, width, total,
                    commit: false),
                onHorizontalDragStart: (d) {
                  setState(() => _dragging = true);
                  _handleTapOrDrag(
                    d.localPosition,
                    width,
                    total,
                    commit: false,
                  );
                },
                onHorizontalDragUpdate: (d) {
                  _handleTapOrDrag(
                    d.localPosition,
                    width,
                    total,
                    commit: false,
                  );
                },
                onHorizontalDragEnd: (_) {
                  if (!_dragging) return;
                  setState(() => _dragging = false);
                  if (!widget.scrubContinuously) {
                    // Commit to final drag position
                    final seekTo = total * _dragFraction;
                    widget.onSeek(seekTo);
                  }
                },
                child: SizedBox(
                  width: width,
                  height: trackHeight + widget.thumbRadius * 2,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Background track
                      Container(
                        height: trackHeight,
                        width: width,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                              BorderRadius.circular(widget.trackRadius),
                        ),
                      ),
                      // Buffered segment
                      Positioned(
                        left: 0,
                        child: Container(
                          height: trackHeight,
                          width: width * bufferedFrac,
                          decoration: BoxDecoration(
                            color: buf,
                            borderRadius:
                                BorderRadius.circular(widget.trackRadius),
                          ),
                        ),
                      ),
                      // Played segment
                      Positioned(
                        left: 0,
                        child: Container(
                          height: trackHeight,
                          width: width * effectivePlayedFrac,
                          decoration: BoxDecoration(
                            color: played,
                            borderRadius:
                                BorderRadius.circular(widget.trackRadius),
                          ),
                        ),
                      ),
                      // Thumb
                      Positioned(
                        left:
                            (width * effectivePlayedFrac) - widget.thumbRadius,
                        child: Container(
                          width: widget.thumbRadius * 2,
                          height: widget.thumbRadius * 2,
                          decoration: BoxDecoration(
                            color: thumb,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Handy default label you can reuse.
class DefaultSeekBarLabel extends StatelessWidget {
  const DefaultSeekBarLabel({
    required this.pos,
    required this.total,
    super.key,
  });
  final Duration pos;
  final Duration total;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(_fmt(pos), style: Theme.of(context).textTheme.labelMedium),
        const Spacer(),
        Text(_fmt(total), style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
