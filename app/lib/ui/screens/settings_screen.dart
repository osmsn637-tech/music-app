import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../data/database/providers.dart';
import '../../features/ai_dj/dj_mode.dart';
import '../../features/connect/connect_models.dart';
import '../../features/connect/providers.dart';
import '../../features/library/storage_info.dart';
import '../../features/sync/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';

final _storageInfoProvider = FutureProvider.autoDispose<StorageInfo>((ref) {
  return StorageInspector().compute();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  final _connectUrlController = TextEditingController();
  final _roomController = TextEditingController();
  final _nameController = TextEditingController();
  bool _initialized = false;
  bool _saved = false;
  bool _connectSaved = false;

  @override
  void dispose() {
    _urlController.dispose();
    _connectUrlController.dispose();
    _roomController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _ensureInitial() async {
    if (_initialized) return;
    final url = await ref.read(serverUrlProvider.future);
    if (url != null && _urlController.text.isEmpty) {
      _urlController.text = url;
    }
    final settings = await ref.read(settingsServiceProvider.future);
    if (_connectUrlController.text.isEmpty) {
      _connectUrlController.text = settings.connectUrl ?? '';
    }
    if (_roomController.text.isEmpty) {
      _roomController.text = settings.roomCode ?? '';
    }
    if (_nameController.text.isEmpty) {
      _nameController.text = settings.deviceName;
    }
    _initialized = true;
  }

  Future<void> _saveConnect() async {
    final settings = await ref.read(settingsServiceProvider.future);
    await settings.setDeviceName(_nameController.text);
    await settings.setRoomCode(_roomController.text);
    await settings.setConnectUrl(_connectUrlController.text);
    await ref.read(connectServiceProvider.notifier).applySettings();
    if (!mounted) return;
    setState(() => _connectSaved = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Live Connect saved')));
  }

  Future<void> _saveUrl() async {
    final settings = await ref.read(settingsServiceProvider.future);
    await settings.setServerUrl(_urlController.text);
    ref.invalidate(serverUrlProvider);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Server URL saved')));
  }

  Future<void> _clearDownloads() async {
    final ok = await showGlassConfirm(
      context,
      title: 'Clear all downloads?',
      body:
          'Removes every downloaded MP3, lyrics, and artwork file. Song metadata, stats, and playlists are also wiped. Re-sync to bring it back.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(appDatabaseProvider);
    final downloader = ref.read(fileDownloaderProvider);
    await StorageInspector().clearDownloads(db: db, downloader: downloader);
    ref.invalidate(_storageInfoProvider);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Downloads cleared')));
  }

  Future<void> _clearHistory() async {
    final ok = await showGlassConfirm(
      context,
      title: 'Clear listening history?',
      body:
          'Resets play counts, completion / skip stats, and per-mode context stats. Favorites and playlists are preserved. The AI DJ will start over from scratch.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(appDatabaseProvider);
    await StorageInspector().clearHistory(db);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('History cleared')));
  }

  Future<void> _pickDefaultMode(DjMode current) async {
    final picked = await showGlassSheet<DjMode>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in DjMode.values)
            if (m != DjMode.general)
              Pressable(
                onTap: () => Navigator.pop(context, m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: LumenTokens.fg(context),
                          ),
                        ),
                      ),
                      if (m == current)
                        const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: LumenTokens.accent,
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
    if (picked != null) ref.read(defaultDjModeProvider.notifier).set(picked);
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitial();
    final djVoice = ref.watch(djVoiceProvider);
    final defaultMode = ref.watch(defaultDjModeProvider);
    final storage = ref.watch(_storageInfoProvider);
    final connect = ref.watch(connectServiceProvider);
    final n = connect.devices.length + 1;
    final connectLabel = !connect.configured
        ? 'Not set up'
        : connect.status == ConnectStatus.connecting
        ? 'Connecting…'
        : connect.connected
        ? '$n device${n == 1 ? '' : 's'} · '
              '${connect.isSelfActive
                  ? 'playing here'
                  : connect.activeRemote != null
                  ? 'playing on ${connect.activeRemote!.name}'
                  : 'idle'}'
        : 'Offline';

    return StageScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LumenTokens.pagePad,
          8,
          LumenTokens.pagePad,
          40,
        ),
        children: [
          GlassSection(
            title: 'Local Wi-Fi server',
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  controller: _urlController,
                  hint: 'http://192.101.2.87:8000',
                  keyboardType: TextInputType.url,
                  onChanged: (_) {
                    if (_saved) setState(() => _saved = false);
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassButton(
                    label: _saved ? 'Saved' : 'Save',
                    primary: !_saved,
                    onPressed: _saved ? null : _saveUrl,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GlassSection(
            title: 'Live Connect',
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Play across your devices. Run the connect service '
                  '(docker compose up -d connect), then enter the same room '
                  'code + its ws:// URL on each device.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: LumenTokens.fgDimOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                GlassField(
                  controller: _nameController,
                  hint: 'This device name',
                  onChanged: (_) {
                    if (_connectSaved) setState(() => _connectSaved = false);
                  },
                ),
                const SizedBox(height: 10),
                GlassField(
                  controller: _roomController,
                  hint: 'Room code',
                  onChanged: (_) {
                    if (_connectSaved) setState(() => _connectSaved = false);
                  },
                ),
                const SizedBox(height: 10),
                GlassField(
                  controller: _connectUrlController,
                  hint: 'ws://192.168.1.20:8002/ws',
                  keyboardType: TextInputType.url,
                  onChanged: (_) {
                    if (_connectSaved) setState(() => _connectSaved = false);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        connectLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: connect.connected
                              ? LumenTokens.accent
                              : LumenTokens.fgDimOf(context),
                        ),
                      ),
                    ),
                    GlassButton(
                      label: _connectSaved ? 'Saved' : 'Save',
                      primary: !_connectSaved,
                      onPressed: _connectSaved ? null : _saveConnect,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GlassSection(
            title: 'AI DJ',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  title: 'DJ voice',
                  subtitle:
                      'Plays a short pre-recorded line from the offline voice '
                      'bank before each track in a DJ queue. No cloud, no TTS.',
                  trailing: Switch(
                    value: djVoice,
                    activeThumbColor: LumenTokens.accent,
                    onChanged: (v) => ref.read(djVoiceProvider.notifier).set(v),
                  ),
                ),
                const _RowDivider(),
                _SettingRow(
                  title: 'Default mode',
                  subtitle: defaultMode.label,
                  trailing: Icon(
                    Icons.chevron_right,
                    color: LumenTokens.fgDim2Of(context),
                  ),
                  onTap: () => _pickDefaultMode(defaultMode),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GlassSection(
            title: 'Storage',
            padding: EdgeInsets.zero,
            child: storage.when(
              loading: () => const _SettingRow(title: 'Calculating…'),
              error: (e, _) => _SettingRow(title: 'Error: $e'),
              data: (info) => Column(
                children: [
                  _SettingRow(title: 'Used', trailing: _Value(info.human)),
                  const _RowDivider(),
                  _SettingRow(
                    title: 'Music',
                    trailing: _Value(formatBytes(info.musicBytes)),
                  ),
                  const _RowDivider(),
                  _SettingRow(
                    title: 'Lyrics',
                    trailing: _Value(formatBytes(info.lyricsBytes)),
                  ),
                  const _RowDivider(),
                  _SettingRow(
                    title: 'Artwork',
                    trailing: _Value(formatBytes(info.artworkBytes)),
                  ),
                  const _RowDivider(),
                  _SettingRow(
                    leading: Icons.cleaning_services_outlined,
                    title: 'Clear all downloads',
                    subtitle: 'Files + metadata + stats + playlists',
                    onTap: _clearDownloads,
                  ),
                  const _RowDivider(),
                  _SettingRow(
                    leading: Icons.history_toggle_off,
                    title: 'Clear listening history',
                    subtitle: 'Resets stats; favorites and playlists are kept',
                    onTap: _clearHistory,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          GlassSection(
            title: 'About',
            padding: const EdgeInsets.all(14),
            child: Text(
              'Personal offline-first music player. Songs are downloaded from '
              'a local Wi-Fi server you run on your computer (Docker + nginx) '
              'and play from local storage on this device.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: LumenTokens.fgDimOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain row used *inside* a [GlassSection] pane (the section is the glass;
/// rows stay transparent so we don't stack blur-on-blur).
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            if (leading != null) ...[
              Icon(leading, size: 20, color: LumenTokens.fgDimOf(context)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LumenTokens.fg(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: LumenTokens.fgDimOf(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: LumenTokens.fgDimOf(context),
        fontFeatures: LumenTokens.tnum,
      ),
    );
  }
}

/// Inset hairline between rows inside a section.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 14, endIndent: 14);
  }
}
