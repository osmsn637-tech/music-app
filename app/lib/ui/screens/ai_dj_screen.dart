import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../features/ai_dj/ai_dj_service.dart';
import '../../features/ai_dj/dj_mode.dart';
import '../../features/ai_dj/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart' show openPlayerRoute;

/// Flacko — the redesigned AI DJ screen.
///
/// The orb is gone. In its place: six big mood cards arranged 2-up.
/// Tapping a card kicks the existing [aiDjQueueControllerProvider] for
/// the matching [DjMode] and routes audio through the same plumbing.
/// Layout follows the JSX kit (`Flacko.jsx`):
///   eyebrow → Flacko display → pitch → Now Mixing strip →
///   "How are you feeling?" → 6 mood cards → request input.
class AiDjScreen extends ConsumerStatefulWidget {
  const AiDjScreen({super.key});

  @override
  ConsumerState<AiDjScreen> createState() => _AiDjScreenState();
}

class _AiDjScreenState extends ConsumerState<AiDjScreen> {
  String _hostLine = '';
  int _lineTick = 0;
  Timer? _lineTimer;
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _hostLine = _newHostLine());
    });
    _lineTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      setState(() {
        _hostLine = _newHostLine();
        _lineTick += 1;
      });
    });
  }

  String _newHostLine() {
    return ref.read(aiDjQueueControllerProvider.notifier).hostBubbleNow();
  }

  @override
  void dispose() {
    _lineTimer?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  void _onSubmitPrompt(DjMode fallback) {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref
        .read(aiDjQueueControllerProvider.notifier)
        .generateFromRequest(text, fallback);
  }

  Future<void> _pickMood(DjMode mode) async {
    final controller = ref.read(aiDjQueueControllerProvider.notifier);
    await controller.generate(mode);
    final queue = ref.read(aiDjQueueControllerProvider).queue;
    if (queue.isNotEmpty) {
      await controller.playAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiDjQueueControllerProvider);
    final defaultMode = ref.watch(defaultDjModeProvider);
    final pickerMode =
        state.mode == DjMode.general ? defaultMode : state.mode;
    final current = state.current;
    final hasQueue = state.queue.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          0, LumenTokens.topSafePad, 0, LumenTokens.bottomSafePad),
      children: [
        // Header — eyebrow → Flacko display → pitch.
        const Padding(
          padding: EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 8),
          child: Text(
            '★ AI DJ · LIVE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: LumenTokens.accent,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 8),
          child: Text(
            'Flacko',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              height: 1.0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 18),
          child: SizedBox(
            width: 280,
            child: Text(
              "A voice host mixing your library — and a few new finds for tonight.",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: LumenTokens.fgDimOf(context),
              ),
            ),
          ),
        ),

        // "Tonight's Set" hero strip — present whether the queue is loaded
        // or not, since the Start pill doubles as the empty-state CTA.
        Padding(
          padding: const EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 18),
          child: _NowMixingCard(
            onStart: () => _pickMood(pickerMode),
            current: current,
            isPlaying: state.isActive,
            onOpenPlayer: () =>
                Navigator.of(context).push(openPlayerRoute()),
          ),
        ),

        // "How are you feeling?" → mood grid.
        const Padding(
          padding: EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 14),
          child: Text(
            'How are you feeling?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _moods.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 96,
            ),
            itemBuilder: (context, i) {
              final m = _moods[i];
              final selected = pickerMode == m.mode && hasQueue;
              return _MoodCard(
                spec: m,
                selected: selected,
                onTap: () => _pickMood(m.mode),
              );
            },
          ),
        ),

        // Intent chips (only when the user requested something specific).
        if (state.intent != null && state.intent!.describe().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LumenTokens.pagePad, 18, LumenTokens.pagePad, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final part in state.intent!.describe())
                  _IntentChip(label: part),
              ],
            ),
          ),

        const SizedBox(height: 18),

        // Free-text request bar — pill-shaped glass, sparkle on the left,
        // pink send circle on the right.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
          child: _RequestField(
            controller: _promptController,
            onSubmit: () => _onSubmitPrompt(pickerMode),
          ),
        ),

        // Host bubble — preserved from the previous design (kept inside a
        // glass card so the voice still has a "speaker" surface).
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
          child: Glass(
            borderRadius: LumenTokens.rXl,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            LumenTokens.orbViolet,
                            LumenTokens.orbPink,
                          ],
                        ),
                      ),
                      child: const Icon(Icons.mic, size: 14),
                    ),
                    const SizedBox(width: 10),
                    const Text('Host',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    _hostLine,
                    key: ValueKey(_lineTick),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LumenTokens.pagePad, 24, LumenTokens.pagePad, 0),
            child: Text(state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

/// Row strip up top — when nothing is queued, shows "Tonight's Set / hosted
/// just for you" + a Start pill that fires Smart Shuffle. Once a queue is
/// running, swaps to the live "now mixing" preview with cover + open arrow.
class _NowMixingCard extends StatelessWidget {
  const _NowMixingCard({
    required this.onStart,
    required this.current,
    required this.isPlaying,
    required this.onOpenPlayer,
  });

  final VoidCallback onStart;
  final AiDjQueueEntry? current;
  final bool isPlaying;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final showLive = current != null && isPlaying;
    return Glass(
      strong: true,
      borderRadius: LumenTokens.rXl,
      padding: const EdgeInsets.all(16),
      child: showLive
          ? _LiveStrip(item: current!, onTap: onOpenPlayer)
          : _StartStrip(onStart: onStart),
    );
  }
}

class _StartStrip extends StatelessWidget {
  const _StartStrip({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOW MIXING',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                  color: LumenTokens.accent,
                ),
              ),
              SizedBox(height: 4),
              Text(
                "Tonight's Set",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Hosted just for you · 47 min',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          borderRadius: BorderRadius.circular(LumenTokens.rPill),
          onTap: onStart,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: LumenTokens.btnPillBg(context),
              borderRadius: BorderRadius.circular(LumenTokens.rPill),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow,
                    size: 14, color: LumenTokens.btnPillFg(context)),
                const SizedBox(width: 6),
                Text(
                  'Start',
                  style: TextStyle(
                    color: LumenTokens.btnPillFg(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveStrip extends StatelessWidget {
  const _LiveStrip({required this.item, required this.onTap});
  final AiDjQueueEntry item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = item.song;
    return InkWell(
      borderRadius: BorderRadius.circular(LumenTokens.rXl),
      onTap: onTap,
      child: Row(
        children: [
          AlbumArt(
            artworkPath: s.localArtworkPath,
            seed: s.id,
            size: 56,
            radius: LumenTokens.r2xs,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NOW MIXING',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: LumenTokens.accent,
                  ),
                ),
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  [s.artist ?? '', s.album ?? '']
                      .where((t) => t.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: LumenTokens.fgDimOf(context)),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: const Icon(Icons.play_arrow, size: 18),
          ),
        ],
      ),
    );
  }
}

/// One mood card — gradient fill, icon top-left, big sentence-cased label
/// at the bottom-left, white-glow border when selected.
class _MoodCard extends StatelessWidget {
  const _MoodCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _MoodSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LumenTokens.rXl),
        onTap: onTap,
        child: AnimatedContainer(
          duration: LumenTokens.dFast,
          curve: LumenTokens.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: spec.gradient,
            borderRadius: BorderRadius.circular(LumenTokens.rXl),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Internal sheen — same diagonal trick as Glass.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(LumenTokens.rXl),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.15),
                        ],
                        stops: const [0.0, 0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(spec.icon, size: 26, color: Colors.white),
                  Text(
                    spec.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestField extends StatelessWidget {
  const _RequestField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: LumenTokens.rPill,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: LumenTokens.accent),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Tell the DJ what you want…',
                hintStyle: TextStyle(
                  color: LumenTokens.fgDim2Of(context),
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(LumenTokens.rPill),
              onTap: onSubmit,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: LumenTokens.accent,
                ),
                child: const Icon(Icons.arrow_forward,
                    size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntentChip extends StatelessWidget {
  const _IntentChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LumenTokens.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(LumenTokens.rXs),
        border: Border.all(
          color: LumenTokens.accent.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: LumenTokens.accent,
        ),
      ),
    );
  }
}

/// Mood card spec — paired with a [DjMode] so taps route through the
/// existing controller.
class _MoodSpec {
  const _MoodSpec({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.mode,
  });
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final DjMode mode;
}

const _moods = <_MoodSpec>[
  _MoodSpec(
    label: 'Smart Shuffle',
    icon: Icons.auto_awesome,
    gradient: LumenTokens.moodSmart,
    mode: DjMode.smartShuffle,
  ),
  _MoodSpec(
    label: 'Focus',
    icon: Icons.format_list_bulleted,
    gradient: LumenTokens.moodFocus,
    mode: DjMode.study,
  ),
  _MoodSpec(
    label: 'Chill',
    icon: Icons.favorite_outline,
    gradient: LumenTokens.moodChill,
    mode: DjMode.chill,
  ),
  _MoodSpec(
    label: 'Workout',
    icon: Icons.shuffle,
    gradient: LumenTokens.moodWorkout,
    mode: DjMode.workout,
  ),
  _MoodSpec(
    label: 'Night Drive',
    icon: Icons.nightlight_round,
    gradient: LumenTokens.moodNight,
    mode: DjMode.night,
  ),
  _MoodSpec(
    label: 'Discover',
    icon: Icons.explore_outlined,
    gradient: LumenTokens.moodDiscover,
    mode: DjMode.discover,
  ),
];
