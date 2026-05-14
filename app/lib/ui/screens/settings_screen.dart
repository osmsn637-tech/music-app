import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../data/database/providers.dart';
import '../../features/ai_dj/dj_mode.dart';
import '../../features/importer/import_providers.dart';
import '../../features/importer/import_service.dart';
import '../../features/library/storage_info.dart';
import '../../features/sync/providers.dart';

/// (done, total, currentName) snapshot driven by the importer's
/// per-file callback. Held in a `ValueNotifier` so only the dialog
/// rebuilds as files stream in.
typedef _ImportTick = ({int done, int total, String currentName});

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

  /// Live progress for the running import (null when idle). The progress
  /// dialog watches this notifier so the per-file callback doesn't
  /// rebuild the rest of the settings tree.
  final ValueNotifier<_ImportTick?> _importProgress =
      ValueNotifier<_ImportTick?>(null);

  @override
  void dispose() {
    _urlController.dispose();
    _importProgress.dispose();
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

  Future<void> _importFiles() async {
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Picker failed: $e')),
      );
      return;
    }
    if (picked == null || picked.paths.isEmpty) return;
    final files = picked.paths
        .whereType<String>()
        .map((path) => File(path))
        .toList();
    if (files.isEmpty || !mounted) return;
    await _runImport(
      (service) => service.importFiles(files, onProgress: _onTick),
    );
  }

  Future<void> _importFolder() async {
    final String? folderPath;
    try {
      folderPath = await FilePicker.platform.getDirectoryPath();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder picker failed: $e')),
      );
      return;
    }
    if (folderPath == null || !mounted) return;
    await _runImport(
      (service) => service.importFolder(
        Directory(folderPath!),
        onProgress: _onTick,
      ),
    );
  }

  void _onTick(int done, int total, String currentName) {
    _importProgress.value = (
      done: done,
      total: total,
      currentName: currentName,
    );
  }

  /// Shared scaffolding for both import flavours: opens the progress
  /// dialog, runs the import, closes the dialog, and reports the
  /// outcome as a snackbar.
  Future<void> _runImport(
    Future<ImportResult> Function(ImportService service) run,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(importServiceProvider);
    _importProgress.value = (done: 0, total: 0, currentName: 'Preparing…');
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(progress: _importProgress),
    );

    ImportResult? result;
    Object? failure;
    try {
      result = await run(service);
    } catch (e) {
      failure = e;
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture; // wait for the pop to settle.

    if (!mounted) return;
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $failure')),
      );
      return;
    }
    final r = result!;
    final parts = <String>[
      'Added ${r.added} ${r.added == 1 ? 'song' : 'songs'}',
      if (r.skipped > 0)
        'skipped ${r.skipped} duplicate${r.skipped == 1 ? '' : 's'}',
      if (r.errors.isNotEmpty)
        '${r.errors.length} error${r.errors.length == 1 ? '' : 's'}',
    ];
    messenger.showSnackBar(SnackBar(content: Text(parts.join(', '))));
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
          _SectionHeader(text: 'Import from device'),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('Import audio files'),
            subtitle: const Text(
              'Pick mp3 / m4a / flac / wav / ogg files from this device',
            ),
            onTap: _importFiles,
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Import folder'),
            subtitle: const Text(
              'Recursively scans a folder for audio and imports each file',
            ),
            onTap: _importFolder,
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

class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog({required this.progress});

  final ValueListenable<_ImportTick?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importing'),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<_ImportTick?>(
          valueListenable: progress,
          builder: (context, tick, _) {
            final t = tick;
            if (t == null) {
              return const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final ratio = t.total > 0 ? t.done / t.total : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: ratio),
                const SizedBox(height: 14),
                Text(
                  t.currentName.isEmpty ? 'Finishing…' : t.currentName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  t.total > 0 ? '${t.done} / ${t.total}' : '',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
