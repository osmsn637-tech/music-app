import 'package:flutter/material.dart';

import '../motion/lumen_route.dart';
import '../screens/settings_screen.dart';
import '../screens/sync_screen.dart';
import 'glass.dart';

/// Sheet that slides up from the top-right profile button. Holds the
/// entry-points the design pulls out of the bottom nav (Sync, Settings).
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ProfileSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Glass(
        strong: true,
        borderRadius: 24,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _Tile(
              icon: Icons.sync_outlined,
              title: 'Sync',
              subtitle: 'Pull songs from your local Wi-Fi server',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context,
                ).pushLumen((_) => const SyncScreen(), axis: LumenAxis.fade);
              },
            ),
            _Tile(
              icon: Icons.tune,
              title: 'Settings',
              subtitle: 'Theme, voice, storage, history',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushLumen(
                  (_) => const SettingsScreen(),
                  axis: LumenAxis.fade,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.white.withValues(alpha: 0.4),
      ),
      onTap: onTap,
    );
  }
}
