import 'package:flutter/material.dart';

/// Animated DJ-voice waveform — 10 bars, varying delays/heights.
class WaveformBars extends StatefulWidget {
  const WaveformBars({
    super.key,
    this.color,
    this.height = 24,
    this.barWidth = 3,
    this.spacing = 3,
    this.animated = true,
  });

  final Color? color;
  final double height;
  final double barWidth;
  final double spacing;
  final bool animated;

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  static const _heights = [0.4, 0.8, 1.0, 0.6, 0.9, 0.3, 0.7, 0.5, 0.95, 0.35];
  static const _delays = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.5, 0.4];

  @override
  void didUpdateWidget(covariant WaveformBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_c.isAnimating) _c.repeat();
    if (!widget.animated && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DefaultTextStyle.of(context).style.color!;
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_heights.length, (i) {
              final phase = (_c.value - _delays[i]) % 1.0;
              final scale = widget.animated
                  ? 0.3 + 0.7 * (0.5 - 0.5 *
                      (1 - 2 * (phase < 0.5 ? phase : 1 - phase)).abs())
                  : _heights[i];
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
                child: Container(
                  width: widget.barWidth,
                  height: widget.height * _heights[i] * scale.clamp(0.15, 1.0),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(widget.barWidth),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// 4-bar visualizer used to mark the currently playing song in lists.
class VisualizerBars extends StatefulWidget {
  const VisualizerBars({
    super.key,
    this.color,
    this.height = 12,
    this.animated = true,
  });

  final Color? color;
  final double height;
  final bool animated;

  @override
  State<VisualizerBars> createState() => _VisualizerBarsState();
}

class _VisualizerBarsState extends State<VisualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  static const _heights = [0.6, 0.9, 0.4, 0.8];
  static const _delays = [0.0, 0.2, 0.4, 0.6];

  @override
  void didUpdateWidget(covariant VisualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_c.isAnimating) _c.repeat();
    if (!widget.animated && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DefaultTextStyle.of(context).style.color!;
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_heights.length, (i) {
              final phase = (_c.value - _delays[i]) % 1.0;
              final scale = widget.animated
                  ? 0.4 + 0.6 *
                      (1 - (1 - 2 * (phase < 0.5 ? phase : 1 - phase)).abs())
                  : 1.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 2,
                  height: widget.height * _heights[i] * scale,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
