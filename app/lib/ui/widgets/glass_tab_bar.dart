import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

class TabSpec {
  const TabSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.accent = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool accent; // Flacko (AI DJ) uses pink
}

/// Compact floating glass pill that sits 16px above the safe-area bottom.
/// Each tab is a small icon + 9.5px label; the active tab gets a soft
/// 10% white wash (or pink for the Flacko/accent tab).
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
  });

  final List<TabSpec> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Glass(
        strong: true,
        borderRadius: LumenTokens.rPill,
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(tabs.length, (i) {
            return Expanded(
              child: _TabItem(
                spec: tabs[i],
                active: i == activeIndex,
                onTap: () => onChanged(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  final TabSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final activeFg =
        spec.accent ? LumenTokens.accent : LumenTokens.fg(context);
    final inactiveFg = LumenTokens.fgDimOf(context);
    final color = active ? activeFg : inactiveFg;

    // Active wash — only on non-accent tabs (Flacko relies on the pink
    // glyph + label for its own visual presence).
    final wash = active && !spec.accent
        ? (isLight
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.10))
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LumenTokens.rPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: LumenTokens.dFast,
          curve: LumenTokens.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LumenTokens.rPill),
            color: wash,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: LumenTokens.dFast,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  active ? spec.activeIcon : spec.icon,
                  key: ValueKey(active),
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                spec.label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
