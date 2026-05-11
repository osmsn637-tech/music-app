import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../data/database/providers.dart';
import '../../features/ai_dj/dj_mode.dart';
import '../../features/library/storage_info.dart';
import '../../features/sync/providers.dart';

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
  bool _initialized = false;
  bool _saved = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _ensureInitial() async {
    if (_initialized) return;
    final url = await ref.read(serverUrlProvider.future);
    if (url != null && _urlController.text.isEmpty) {
      _urlController.text = url;
    }
    _initialized = true;
  }

  Future<void> _saveUrl() async {
    final settings = await ref.read(settingsServiceProvider.future);
    await settings.setServerUrl(_urlController.text);
    ref.invalidate(serverUrlProvider);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server URL saved')),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _clearDownloads() async {
    final ok = await _confirm(
      title: 'Clear all downloads?',
      body:
          'Removes every downloaded MP3, lyrics, and artwork file. Song metadata, stats, and playlists are also wiped. Re-sync to bring it back.',
      confirmLabel: 'Clear',
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
    final ok = await _confirm(
      title: 'Clear listening history?',
      body:
          'Resets play counts, completion / skip stats, and per-mode context stats. Favorites and playlists are preserved. The AI DJ will start over from scratch.',
      confirmLabel: 'Clear',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(appDatabaseProvider);
    await StorageInspector().clearHistory(db);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('History cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitial();
    final themeMode = ref.watch(themeModeProvider);
    final djVoice = ref.watch(djVoiceProvider);
    final defaultMode = ref.watch(defaultDjModeProvider);
    final liveWallpaper = ref.watch(liveWallpaperProvider);
    final storage = ref.watch(_storageInfoProvider);

    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(text: 'Local Wi-Fi server'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.20:8000',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() => _saved = false),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _saved ? null : _saveUrl,
                    child: Text(_saved ? 'Saved' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(text: 'Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (m) {
              if (m != null) ref.read(themeModeProvider.notifier).set(m);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('System'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Live wallpaper'),
            subtitle: const Text(
              'Drifting, touch-reactive blobs in the background. Turn off '
              'for a cleaner look that lets the glass UI breathe.',
            ),
            value: liveWallpaper,
            onChanged: (v) =>
                ref.read(liveWallpaperProvider.notifier).set(v),
          ),
          const Divider(height: 32),
          _SectionHeader(text: 'AI DJ'),
          SwitchListTile(
            title: const Text('DJ voice'),
            subtitle: const Text(
              'Plays a short pre-recorded line from the offline voice bank '
              'before each track in a DJ queue. No cloud, no TTS — clips '
              'live in <app docs>/dj_voice_bank/.',
            ),
            value: djVoice,
            onChanged: (v) => ref.read(djVoiceProvider.notifier).set(v),
          ),
          ListTile(
            title: const Text('Default mode'),
            subtitle: Text(defaultMode.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<DjMode>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Default DJ mode'),
                  children: [
                    for (final m in DjMode.values)
                      if (m != DjMode.general)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, m),
                          child: Text(m.label),
                        ),
                  ],
                ),
              );
              if (picked != null) {
                ref.read(defaultDjModeProvider.notifier).set(picked);
              }
            },
          ),
          const Divider(height: 32),
          _SectionHeader(text: 'Storage'),
          storage.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Calculating…'),
            ),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (info) => Column(
              children: [
                ListTile(
                  title: const Text('Used'),
                  trailing: Text(info.human),
                ),
                ListTile(
                  title: const Text('Music'),
                  trailing: Text(formatBytes(info.musicBytes)),
                ),
                ListTile(
                  title: const Text('Lyrics'),
                  trailing: Text(formatBytes(info.lyricsBytes)),
                ),
                ListTile(
                  title: const Text('Artwork'),
                  trailing: Text(formatBytes(info.artworkBytes)),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear all downloads'),
            subtitle: const Text('Files + metadata + stats + playlists'),
            onTap: _clearDownloads,
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Clear listening history'),
            subtitle: const Text(
              'Resets stats; favorites and playlists are kept',
            ),
            onTap: _clearHistory,
          ),
          const Divider(height: 32),
          _SectionHeader(text: 'About'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'Personal offline-first music player. Songs are downloaded from '
              'a local Wi-Fi server you run on your computer (Docker + nginx) '
              'and play from local storage on this device.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
