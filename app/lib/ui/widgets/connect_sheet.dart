import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/connect/providers.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';

/// Opens the Live Connect device picker ("Play on…") as a bottom sheet.
/// Shared by the desktop now-playing bar and the mobile full player so a
/// handoff can be started from either.
Future<void> showConnectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF121216),
    showDragHandle: true,
    builder: (_) => const ConnectDeviceSheet(),
  );
}

class ConnectDeviceSheet extends ConsumerWidget {
  const ConnectDeviceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(connectServiceProvider);
    final svc = ref.read(connectServiceProvider.notifier);
    final fg = LumenTokens.fg(context);

    if (!c.configured) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Live Connect isn't set up",
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add the connect URL + room code in Settings → Live Connect, '
                'then open Flacko on your other devices with the same code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LumenTokens.fgDimOf(context),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live "playing on <other device>" card with a self-ticking
            // progress bar + a Continue-here pull. Hides itself when nothing
            // is playing on another device.
            const _RemoteNowPlaying(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                c.connected ? 'Play on…' : 'Connecting…',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final d in c.devices)
              _DeviceRow(
                name: d.name,
                platform: d.platform,
                active: d.deviceId == c.activeDeviceId,
                onTap: d.deviceId == c.activeDeviceId
                    ? null
                    : () {
                        svc.transferTo(d.deviceId);
                        Navigator.pop(context);
                      },
              ),
            if (c.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Text(
                  'No other devices online. Open Flacko on another device with '
                  'the same room code.',
                  style: TextStyle(
                    color: LumenTokens.fgDim2Of(context),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.platform,
    required this.active,
    this.onTap,
  });

  final String name;
  final String platform;
  final bool active;
  final VoidCallback? onTap;

  IconData get _icon => switch (platform) {
    'macos' || 'windows' || 'linux' => Icons.laptop_mac,
    'ios' || 'android' => Icons.phone_iphone,
    'self' => Icons.headphones,
    _ => Icons.devices_other,
  };

  @override
  Widget build(BuildContext context) {
    final color = active ? LumenTokens.accent : LumenTokens.fg(context);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(_icon, size: 22, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (active)
              const Icon(
                Icons.equalizer_rounded,
                size: 18,
                color: LumenTokens.accent,
              ),
          ],
        ),
      ),
    );
  }
}

/// Live card for the device the room is currently playing on (when that's not
/// us). Self-ticks a progress bar — the source only heartbeats every ~5s, so
/// we extrapolate — and offers "Continue here" to pull playback onto this
/// device from the exact spot. Hides itself when nothing's playing remotely.
class _RemoteNowPlaying extends ConsumerStatefulWidget {
  const _RemoteNowPlaying();

  @override
  ConsumerState<_RemoteNowPlaying> createState() => _RemoteNowPlayingState();
}

class _RemoteNowPlayingState extends ConsumerState<_RemoteNowPlaying> {
  Timer? _tick;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _continueHere() async {
    final navigator = Navigator.of(context);
    final ok = await ref.read(connectServiceProvider.notifier).continueHere();
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _msg = "That song isn't downloaded on this device.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(connectServiceProvider);
    final remote = c.activeRemote;
    final sess = c.session;
    if (remote == null || sess == null) return const SizedBox.shrink();

    final songId = sess.currentSongId;
    final songAsync =
        songId == null ? null : ref.watch(songByIdProvider(songId));
    final song = songAsync?.valueOrNull;
    final notHere = songAsync != null && !songAsync.isLoading && song == null;

    final posMs = sess.livePositionMs(DateTime.now().millisecondsSinceEpoch);
    final durMs = song?.durationMs ?? 0;
    final frac = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final title = song?.title ?? 'Playing on ${remote.name}';
    final artist = song?.artist;
    final fg = LumenTokens.fg(context);
    final dim2 = LumenTokens.fgDim2Of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_platformIcon(remote.platform),
                  size: 16, color: LumenTokens.accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Playing on ${remote.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: LumenTokens.fgDimOf(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          if (artist != null && artist.isNotEmpty)
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: LumenTokens.fgDimOf(context), fontSize: 12.5),
            ),
          const SizedBox(height: 10),
          if (durMs > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(LumenTokens.accent),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_clock(posMs), style: TextStyle(color: dim2, fontSize: 11)),
                if (durMs > 0)
                  Text(_clock(durMs), style: TextStyle(color: dim2, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Pressable(
            onTap: notHere ? null : _continueHere,
            child: Opacity(
              opacity: notHere ? 0.45 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LumenTokens.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  notHere ? 'Not downloaded here' : 'Continue here',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                _msg!,
                textAlign: TextAlign.center,
                style: TextStyle(color: dim2, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
        ],
      ),
    );
  }
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

IconData _platformIcon(String platform) => switch (platform) {
  'macos' || 'windows' || 'linux' => Icons.laptop_mac,
  'ios' || 'android' => Icons.phone_iphone,
  _ => Icons.devices_other,
};
