import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../features/library/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';

// Tempo bounds (speed multiplier). The BPM slider is anchored to the track's
// own tempo, so these also cap how far above/below the original BPM you can go.
const double _kMinSpeed = 0.5;
const double _kMaxSpeed = 2.0;
const List<double> _kSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
// Quick BPM nudges, relative to the track's original tempo.
const List<int> _kBpmNudges = [-10, -5, 5, 10];

/// Opens the per-song tempo control. Edits [song]'s saved tempo (persisted
/// to the DB and applied whenever it plays); previews live if it's the
/// currently playing song.
Future<void> showTempoSheet(BuildContext context, SongRow song) =>
    showGlassSheet<void>(context, child: _TempoSheet(song: song));

/// Live per-song tempo (speed multiplier) read from the reactive song list so
/// it doesn't go stale after an edit (mirrors the favorite-state pattern).
double liveTempoScale(WidgetRef ref, SongRow song) {
  final live = ref.watch(allSongsProvider).valueOrNull;
  final match = live?.cast<SongRow?>().firstWhere(
    (s) => s?.id == song.id,
    orElse: () => null,
  );
  return (match ?? song).tempoScale;
}

/// "1×", "1.25×", "1.05×" — no trailing zeros.
String formatTempo(double s) {
  final r = (s * 100).round() / 100;
  if (r == r.roundToDouble()) return '${r.toStringAsFixed(0)}×';
  var str = r.toStringAsFixed(2);
  if (str.endsWith('0')) str = str.substring(0, str.length - 1);
  return '$str×';
}

/// "12% slower" / "8% faster" / "" (at original).
String tempoDelta(double scale) {
  final pct = ((scale - 1.0) * 100).round();
  if (pct == 0) return '';
  return '${pct.abs()}% ${pct > 0 ? 'faster' : 'slower'}';
}

class _TempoSheet extends ConsumerStatefulWidget {
  const _TempoSheet({required this.song});

  final SongRow song;

  @override
  ConsumerState<_TempoSheet> createState() => _TempoSheetState();
}

class _TempoSheetState extends ConsumerState<_TempoSheet> {
  late double _scale = widget.song.tempoScale;

  /// Updates the scale: always previews live audio (when this is the playing
  /// song); persists to the DB on discrete actions and drag-end only.
  void _apply(double scale, {required bool persist}) {
    final clamped = scale.clamp(_kMinSpeed, _kMaxSpeed);
    setState(() => _scale = clamped);
    if (ref.read(nowPlayingProvider)?.id == widget.song.id) {
      ref.read(playerServiceProvider).setActiveTempo(clamped);
    }
    if (persist) {
      ref.read(songRepositoryProvider).setTempoScale(widget.song.id, clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bpm = widget.song.bpm ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Tempo', style: glassEyebrow(context)),
          ),
          const SizedBox(height: 16),
          if (bpm > 0) _bpmControl(bpm) else _speedControl(),
        ],
      ),
    );
  }

  // BPM-target control — primary mode when the track has an analyzed BPM.
  Widget _bpmControl(int originalBpm) {
    final minBpm = (originalBpm * _kMinSpeed).round();
    final maxBpm = (originalBpm * _kMaxSpeed).round();
    final targetBpm = (originalBpm * _scale).round().clamp(minBpm, maxBpm);
    final active = targetBpm != originalBpm;
    final delta = tempoDelta(_scale);
    final headColor = active ? LumenTokens.accent : LumenTokens.fg(context);

    void setBpm(int target, {bool persist = true}) {
      final t = target.clamp(minBpm, maxBpm);
      // Keep full precision so the BPM round-trips exactly (no rounding drift).
      _apply(t / originalBpm, persist: persist);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Big target-BPM readout with − / + fine steppers (±1 BPM).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: () => setBpm(targetBpm - 1),
            ),
            const SizedBox(width: 22),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$targetBpm',
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: headColor,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  active
                      ? 'BPM  ·  was $originalBpm  ·  $delta'
                      : 'BPM  ·  original tempo',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: LumenTokens.fgDimOf(context),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 22),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: () => setBpm(targetBpm + 1),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // BPM slider — integer steps, snaps onto the original tempo.
        _trackTheme(
          child: Slider(
            min: minBpm.toDouble(),
            max: maxBpm.toDouble(),
            divisions: maxBpm - minBpm,
            value: targetBpm.toDouble(),
            onChanged: (v) {
              final t = v.round();
              setBpm(
                (t - originalBpm).abs() <= 1 ? originalBpm : t,
                persist: false,
              );
            },
            onChangeEnd: (_) => ref
                .read(songRepositoryProvider)
                .setTempoScale(widget.song.id, _scale),
          ),
        ),
        const SizedBox(height: 4),

        // Relative BPM nudge chips.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in _kBpmNudges)
              _Chip(
                label: '${n > 0 ? '+' : ''}$n',
                selected: targetBpm == originalBpm + n,
                onTap: () => setBpm(originalBpm + n),
              ),
          ],
        ),

        if (active)
          _resetButton(() => setBpm(originalBpm), 'Reset to original'),
      ],
    );
  }

  // Fallback when the track has no analyzed BPM — plain speed multiplier.
  Widget _speedControl() {
    final active = (_scale - 1.0).abs() > 0.001;
    final headColor = active ? LumenTokens.accent : LumenTokens.fg(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                formatTempo(_scale),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: headColor,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                active
                    ? tempoDelta(_scale)
                    : 'No BPM yet — analyze the track to match by BPM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: LumenTokens.fgDimOf(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _trackTheme(
          child: Slider(
            min: _kMinSpeed,
            max: _kMaxSpeed,
            value: _scale.clamp(_kMinSpeed, _kMaxSpeed),
            onChanged: (v) {
              final snapped = (v - 1.0).abs() < 0.03 ? 1.0 : v;
              _apply((snapped * 100).round() / 100, persist: false);
            },
            onChangeEnd: (_) => ref
                .read(songRepositoryProvider)
                .setTempoScale(widget.song.id, _scale),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _kSpeedPresets)
              _Chip(
                label: formatTempo(p),
                selected: (_scale - p).abs() < 0.001,
                onTap: () => _apply(p, persist: true),
              ),
          ],
        ),
        if (active) _resetButton(() => _apply(1.0, persist: true), 'Reset'),
      ],
    );
  }

  Widget _trackTheme({required Widget child}) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      activeTrackColor: LumenTokens.accent,
      thumbColor: LumenTokens.accent,
      inactiveTrackColor: LumenTokens.fgDim2Of(context).withValues(alpha: 0.20),
      overlayColor: LumenTokens.accent.withValues(alpha: 0.15),
      trackHeight: 4,
    ),
    child: child,
  );

  Widget _resetButton(VoidCallback onTap, String label) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Center(
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: LumenTokens.accent,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Compact ↑/↓ + BPM indicator shown under a song's name when its tempo has
/// been changed from the original. Renders nothing at original tempo.
class TempoBadge extends ConsumerWidget {
  const TempoBadge({super.key, required this.song});

  final SongRow song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = liveTempoScale(ref, song);
    final atOriginal = (scale - 1.0).abs() < 0.001;
    final up = scale > 1.0;
    final bpm = song.bpm ?? 0;
    final label = bpm > 0 ? '${(bpm * scale).round()} BPM' : tempoDelta(scale);
    return AnimatedSwitcher(
      duration: LumenTokens.mBase,
      transitionBuilder: (child, anim) => SizeTransition(
        sizeFactor: anim,
        axisAlignment: -1,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: atOriginal
          ? const SizedBox.shrink()
          : Padding(
              key: const ValueKey('tempo'),
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    up
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 13,
                    color: LumenTokens.accent,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: LumenTokens.accent,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LumenTokens.fgDim2Of(context).withValues(alpha: 0.12),
        ),
        child: Icon(icon, size: 24, color: LumenTokens.fg(context)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? LumenTokens.accent.withValues(alpha: 0.18)
              : LumenTokens.fgDim2Of(context).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? LumenTokens.accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? LumenTokens.accent : LumenTokens.fg(context),
          ),
        ),
      ),
    );
  }
}
