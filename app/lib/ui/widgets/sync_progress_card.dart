import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../features/sync/sync_models.dart';

const _accentGreen = Color(0xFF34C759);
const _accentRed = Color(0xFFFF453A);

enum _Phase { idle, working, success, failed }

class _Resolved {
  const _Resolved({
    required this.phase,
    required this.ringProgress,
    required this.label,
    required this.caption,
    required this.subtitle,
  });
  final _Phase phase;
  final double ringProgress;
  final String label;
  final String caption;
  final String subtitle;
}

_Resolved _resolve(SyncProgress p) {
  if (p.error != null) {
    return _Resolved(
      phase: _Phase.failed,
      ringProgress: 0,
      label: 'Sync failed',
      caption: p.error!,
      subtitle: '',
    );
  }
  if (!p.running && p.items.isEmpty) {
    return const _Resolved(
      phase: _Phase.idle,
      ringProgress: 0,
      label: 'Ready',
      caption: 'Tap Sync to start',
      subtitle: '',
    );
  }

  SyncItem? current;
  for (final i in p.items) {
    if (i.status == SyncItemStatus.downloading) {
      current = i;
      break;
    }
  }

  if (p.running) {
    final completed = p.done + p.skipped + p.deleted + p.failed;
    final currentFrac = current != null && current.bytesTotal > 0
        ? (current.bytesReceived / current.bytesTotal).clamp(0.0, 1.0)
        : 0.0;
    final ring = p.total > 0
        ? ((completed + currentFrac) / p.total).clamp(0.0, 1.0)
        : 0.0;
    return _Resolved(
      phase: _Phase.working,
      ringProgress: ring,
      label: '$completed of ${p.total}',
      caption: current?.title ?? p.message ?? 'Working',
      subtitle: 'Downloading',
    );
  }

  if (p.failed > 0) {
    return _Resolved(
      phase: _Phase.failed,
      ringProgress: 1,
      label: '${p.failed} failed',
      caption: '${p.done} synced • ${p.failed} failed',
      subtitle: 'Sync incomplete',
    );
  }

  return _Resolved(
    phase: _Phase.success,
    ringProgress: 1,
    label: 'Synced',
    caption: _successCaption(p),
    subtitle: 'Up to date',
  );
}

String _successCaption(SyncProgress p) {
  final parts = <String>[];
  if (p.done > 0) parts.add('${p.done} new');
  if (p.skipped > 0) parts.add('${p.skipped} unchanged');
  if (p.deleted > 0) parts.add('${p.deleted} removed');
  return parts.isEmpty ? 'No changes' : parts.join(' • ');
}

class SyncProgressCard extends StatelessWidget {
  const SyncProgressCard({super.key, required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(progress);
    if (resolved.phase == _Phase.idle) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProgressRing(progress: resolved.ringProgress, phase: resolved.phase),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey('${resolved.phase}-${resolved.label}'),
              children: [
                Text(
                  resolved.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  resolved.caption,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatefulWidget {
  const _ProgressRing({required this.progress, required this.phase});

  final double progress;
  final _Phase phase;

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing>
    with TickerProviderStateMixin {
  late final AnimationController _completion;
  late final Animation<double> _ringTopUp;
  late final Animation<double> _percentFade;
  late final Animation<double> _markDraw;
  late final Animation<double> _scale;

  late final AnimationController _liveCtrl;
  Animation<double> _liveAnim = const AlwaysStoppedAnimation(0);
  double _liveBase = 0;

  @override
  void initState() {
    super.initState();
    _completion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _ringTopUp = CurvedAnimation(
      parent: _completion,
      curve: const Interval(0.0, 0.42, curve: Curves.easeOutCubic),
    );
    _percentFade = CurvedAnimation(
      parent: _completion,
      curve: const Interval(0.05, 0.32, curve: Curves.easeOut),
    );
    _markDraw = CurvedAnimation(
      parent: _completion,
      curve: const Interval(0.42, 1.0, curve: Curves.easeOutCubic),
    );
    _scale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(
              begin: 1.0,
              end: 1.06,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 45,
          ),
          TweenSequenceItem(
            tween: Tween(
              begin: 1.06,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeIn)),
            weight: 55,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _completion,
            curve: const Interval(0.42, 1.0),
          ),
        );

    _liveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _liveBase = widget.progress;
    _liveAnim = AlwaysStoppedAnimation(widget.progress);

    if (widget.phase == _Phase.success || widget.phase == _Phase.failed) {
      _completion.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_ProgressRing old) {
    super.didUpdateWidget(old);

    final terminal =
        widget.phase == _Phase.success || widget.phase == _Phase.failed;

    if (widget.phase == _Phase.working && widget.progress != _liveBase) {
      _liveAnim = Tween<double>(
        begin: _liveBase,
        end: widget.progress,
      ).animate(CurvedAnimation(parent: _liveCtrl, curve: Curves.easeOut));
      _liveBase = widget.progress;
      _liveCtrl.forward(from: 0);
    }

    final wasTerminal =
        old.phase == _Phase.success || old.phase == _Phase.failed;
    if (!wasTerminal && terminal) {
      _completion.forward(from: 0);
    } else if (wasTerminal && !terminal) {
      _completion.value = 0;
    }
  }

  @override
  void dispose() {
    _completion.dispose();
    _liveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_completion, _liveCtrl]),
      builder: (context, _) {
        final terminal =
            widget.phase == _Phase.success || widget.phase == _Phase.failed;
        final live = _liveAnim.value.clamp(0.0, 1.0);
        final ringValue = terminal
            ? lerpDouble(live, 1.0, _ringTopUp.value)!
            : live;
        final scale = terminal ? _scale.value : 1.0;
        final percent = (widget.progress * 100).clamp(0, 100).round();

        return RepaintBoundary(
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 132,
              height: 132,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: ringValue,
                  markProgress: terminal ? _markDraw.value : 0,
                  phase: widget.phase,
                ),
                child: Center(
                  child: Opacity(
                    opacity: terminal
                        ? (1 - _percentFade.value).clamp(0.0, 1.0)
                        : 1.0,
                    child: Text(
                      '$percent%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.markProgress,
    required this.phase,
  });

  final double progress;
  final double markProgress;
  final _Phase phase;

  static const _stroke = 6.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - _stroke) / 2;
    final color = phase == _Phase.failed ? _accentRed : _accentGreen;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = _stroke
        ..style = PaintingStyle.stroke,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    if (markProgress > 0) {
      _drawMark(canvas, center, radius, color);
    }
  }

  void _drawMark(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (phase == _Phase.failed) {
      // X mark — two diagonals.
      final span = r * 0.34;
      path.moveTo(c.dx - span, c.dy - span);
      path.lineTo(c.dx + span, c.dy + span);
      path.moveTo(c.dx + span, c.dy - span);
      path.lineTo(c.dx - span, c.dy + span);
    } else {
      // Apple Pay-style checkmark.
      path.moveTo(c.dx - r * 0.32, c.dy + r * 0.04);
      path.lineTo(c.dx - r * 0.06, c.dy + r * 0.28);
      path.lineTo(c.dx + r * 0.36, c.dy - r * 0.22);
    }

    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    final target = total * markProgress.clamp(0.0, 1.0);
    final partial = Path();
    var remaining = target;
    for (final m in metrics) {
      if (remaining <= 0) break;
      final extract = m.extractPath(0, math.min(remaining, m.length));
      partial.addPath(extract, Offset.zero);
      remaining -= m.length;
    }
    canvas.drawPath(partial, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.markProgress != markProgress ||
      old.phase != phase;
}
