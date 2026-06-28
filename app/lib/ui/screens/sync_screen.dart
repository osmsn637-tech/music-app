import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../data/sources/manifest_api.dart';
import '../../features/sync/providers.dart';
import '../../features/sync/sync_models.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/glass_kit.dart';
import '../widgets/sync_progress_card.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _controller = TextEditingController();
  final _urlFocus = FocusNode();
  bool _initialized = false;
  bool _editing = false;
  ConnectionTestResult? _lastTest;
  bool _testing = false;

  @override
  void dispose() {
    _controller.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  Future<void> _ensureInitialUrl() async {
    if (_initialized) return;
    final url = await ref.read(serverUrlProvider.future);
    if (url != null && _controller.text.isEmpty) {
      _controller.text = url;
    }
    _initialized = true;
  }

  Future<void> _persistUrl() async {
    final settings = await ref.read(settingsServiceProvider.future);
    await settings.setServerUrl(_controller.text);
    ref.invalidate(serverUrlProvider);
  }

  Future<void> _onTest() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _testing = true);
    await _persistUrl();
    final api = ref.read(manifestApiProvider);
    final result = await api.testConnection(_controller.text.trim());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _lastTest = result;
      if (result.ok) _editing = false;
    });
  }

  Future<void> _onSync() async {
    if (_controller.text.trim().isEmpty) return;
    await _persistUrl();
    if (mounted) setState(() => _editing = false);
    await ref
        .read(syncControllerProvider.notifier)
        .run(_controller.text.trim());
  }

  void _beginEditing() {
    setState(() {
      _editing = true;
      _lastTest = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _urlFocus.requestFocus();
    });
  }

  void _dismissEditor() {
    if (_urlFocus.hasFocus) _urlFocus.unfocus();
    final saved = (ref.read(serverUrlProvider).valueOrNull ?? '').trim();
    if (saved.isNotEmpty && _editing) {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialUrl();
    // The screen root deliberately does NOT watch syncControllerProvider.
    // That provider emits dozens of times per second during a sync. The
    // structural pieces (URL pill, test result, layout) only need
    // savedUrl + _editing + _testing + _lastTest. The progress-driven
    // bits (action buttons, progress card, activity log) are extracted
    // into ConsumerWidget leaves that scope their own watches.
    final scheme = Theme.of(context).colorScheme;
    final savedUrl = (ref.watch(serverUrlProvider).valueOrNull ?? '').trim();
    final showEditor = _editing || savedUrl.isEmpty;

    return StageScaffold(
      title: 'Sync',
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissEditor,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.04, 0.94, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: showEditor
                          ? GlassField(
                              key: const ValueKey('editor'),
                              controller: _controller,
                              focusNode: _urlFocus,
                              autofocus: savedUrl.isNotEmpty,
                              onSubmitted: (_) => _dismissEditor(),
                              hint: 'http://192.101.2.87:8000',
                              keyboardType: TextInputType.url,
                            )
                          : _ServerUrlPill(
                              key: const ValueKey('pill'),
                              url: savedUrl,
                              onTap: _beginEditing,
                            ),
                    ),
                    const SizedBox(height: 12),
                    _SyncActionsRow(
                      testing: _testing,
                      onTest: _onTest,
                      onSync: _onSync,
                    ),
                    if (_lastTest != null) ...[
                      const SizedBox(height: 12),
                      _TestResultBanner(result: _lastTest!, scheme: scheme),
                    ],
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
              const _SyncProgressSliver(),
              const _RecentLogSliver(),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Action buttons. Only watches `progress.running` via [select] so
/// per-byte sync emissions don't rebuild this row.
class _SyncActionsRow extends ConsumerWidget {
  const _SyncActionsRow({
    required this.testing,
    required this.onTest,
    required this.onSync,
  });

  final bool testing;
  final Future<void> Function() onTest;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(syncControllerProvider.select((p) => p.running));
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            label: 'Test connection',
            icon: Icons.wifi_tethering,
            expand: true,
            loading: testing,
            onPressed: (testing || running) ? null : onTest,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GlassButton(
            label: 'Sync',
            icon: Icons.sync,
            primary: true,
            expand: true,
            loading: running,
            onPressed: running ? null : onSync,
          ),
        ),
      ],
    );
  }
}

class _TestResultBanner extends StatelessWidget {
  const _TestResultBanner({required this.result, required this.scheme});

  final ConnectionTestResult result;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // Glass surface; the semantic ok/error colour rides only the icon +
    // text so the card stays in the frosted language instead of a flat
    // green/red fill.
    final accent = result.ok ? const Color(0xFF54E39B) : scheme.error;
    return Glass(
      borderRadius: LumenTokens.rMd,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            result.ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.message,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: LumenTokens.fg(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress card sliver. Self-watches the sync controller so its rebuild
/// stays scoped to itself plus the activity log — the rest of the screen
/// (URL pill, action buttons, layout) is unaffected by per-byte ticks.
class _SyncProgressSliver extends ConsumerWidget {
  const _SyncProgressSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(syncControllerProvider);
    final visible =
        progress.running || progress.items.isNotEmpty || progress.error != null;
    if (!visible) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverToBoxAdapter(
        child: RepaintBoundary(child: SyncProgressCard(progress: progress)),
      ),
    );
  }
}

class _RecentLogSliver extends ConsumerWidget {
  const _RecentLogSliver();

  static const _maxRows = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(syncControllerProvider.select((p) => p.items));
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final tail = items.length > _maxRows
        ? items.sublist(items.length - _maxRows)
        : items;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                items.length > _maxRows
                    ? 'Recent activity (last $_maxRows of ${items.length})'
                    : 'Activity',
                style: TextStyle(
                  color: LumenTokens.fgDim2Of(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: tail.length,
            itemBuilder: (context, i) =>
                RepaintBoundary(child: _SyncItemRow(tail[i])),
          ),
        ],
      ),
    );
  }
}

class _ServerUrlPill extends StatelessWidget {
  const _ServerUrlPill({super.key, required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Glass(
        borderRadius: LumenTokens.rMd,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Importing from',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: LumenTokens.fg(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: LumenTokens.fgDimOf(context),
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncItemRow extends StatelessWidget {
  const _SyncItemRow(this.item);

  final SyncItem item;

  IconData get _icon {
    switch (item.status) {
      case SyncItemStatus.pending:
        return Icons.schedule;
      case SyncItemStatus.downloading:
        return Icons.downloading;
      case SyncItemStatus.success:
        return Icons.check_circle;
      case SyncItemStatus.skipped:
        return Icons.skip_next;
      case SyncItemStatus.failed:
        return Icons.error;
      case SyncItemStatus.deleted:
        return Icons.delete_outline;
      case SyncItemStatus.repaired:
        return Icons.healing;
    }
  }

  Color _color(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    switch (item.status) {
      case SyncItemStatus.success:
        return s.primary;
      case SyncItemStatus.failed:
        return s.error;
      case SyncItemStatus.deleted:
        return s.error.withValues(alpha: 0.7);
      default:
        return s.onSurfaceVariant;
    }
  }

  String _trailing() {
    if (item.status == SyncItemStatus.downloading && item.bytesTotal > 0) {
      final pct = (item.bytesReceived / item.bytesTotal * 100).clamp(0, 100);
      return '${pct.toStringAsFixed(0)}%';
    }
    if (item.status == SyncItemStatus.failed) return 'failed';
    if (item.status == SyncItemStatus.skipped) return 'skipped';
    if (item.status == SyncItemStatus.deleted) return 'removed';
    if (item.status == SyncItemStatus.success) return 'ok';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(_icon, size: 20, color: _color(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: LumenTokens.fg(context),
                  ),
                ),
                if (item.error != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_trailing().isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              _trailing(),
              style: TextStyle(
                fontSize: 12.5,
                color: LumenTokens.fgDimOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
