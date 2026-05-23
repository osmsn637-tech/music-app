import 'package:flutter/material.dart';

/// Lumen design tokens — iOS 26 liquid-glass redesign.
///
/// Source of truth: `music-app/project/colors_and_type.css` from the
/// Lumen design bundle. Extends the legacy palette with a 5-phase
/// time-of-day wallpaper, theme-aware glass tints, and a typed ramp.
class LumenTokens {
  // ─── Stage (under everything) ─────────────────────────────────────────
  static const stageBg = Color(0xFF050507);
  static const surfaceBg = Color(0xFF0A0A0C);
  static const lightStageBg = Color(0xFFF3F1EE); // warm cream

  // ─── Brand ────────────────────────────────────────────────────────────
  /// Primary pink. Active tabs, hearts, AI/DJ accents. Never a card fill.
  static const accent = Color(0xFFFF7AA8);
  /// High-contrast variant used on light-mode pill buttons / labels.
  static const accentStrong = Color(0xFFD63384);

  // ─── Orb gradient stops (mood backdrops, host avatar, feature cards) ──
  static const orbViolet = Color(0xFFB8A8FF);
  static const orbPink = Color(0xFFFF7EB6);
  static const orbCyan = Color(0xFF5BE0FF);
  static const orbGold = Color(0xFFFFD36B);
  static const orbDeep = Color(0xFF2A1F5E);

  // ─── Legacy blob anchors (kept for back-compat — wallpaper now uses
  //     the TOD palette below). ────────────────────────────────────────
  static const blobPurple = Color(0xFF6B5BFF);
  static const blobPink = Color(0xFFFF6B9D);
  static const lightBlobPurple = Color(0xFFB8B3FF);
  static const lightBlobPink = Color(0xFFFFC4D8);

  // ─── Glass tints — dark ───────────────────────────────────────────────
  static const glassTintWeak = Color(0x0FFFFFFF);   // 6% white
  static const glassTintStrong = Color(0x1AFFFFFF); // 10% white
  static const glassBorderWeak = Color(0x14FFFFFF); // 8%
  static const glassBorderStrong = Color(0x1FFFFFFF); // 12%

  // ─── Glass tints — light ──────────────────────────────────────────────
  static Color get glassTintWeakLight =>
      Colors.white.withValues(alpha: 0.55);
  static Color get glassTintStrongLight =>
      Colors.white.withValues(alpha: 0.70);
  static Color get glassBorderWeakLight =>
      Colors.white.withValues(alpha: 0.70);
  static Color get glassBorderStrongLight =>
      Colors.white.withValues(alpha: 0.85);

  // ─── Foreground — dark ────────────────────────────────────────────────
  static const fgPrimary = Color(0xFFFFFFFF);
  static Color fgDim = Colors.white.withValues(alpha: 0.55);
  static Color fgDim2 = Colors.white.withValues(alpha: 0.38);
  static Color fgDisabled = Colors.white.withValues(alpha: 0.24);

  // ─── Foreground — light ───────────────────────────────────────────────
  static const fgLightPrimary = Color(0xFF111111);
  static Color fgLightDim = const Color(0xFF111111).withValues(alpha: 0.62);
  static Color fgLightDim2 = const Color(0xFF111111).withValues(alpha: 0.45);
  static Color fgLightDisabled =
      const Color(0xFF111111).withValues(alpha: 0.28);

  /// Theme-aware primary foreground.
  static Color fg(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? fgPrimary : fgLightPrimary;
  /// Theme-aware dim (meta).
  static Color fgDimOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? fgDim : fgLightDim;
  /// Theme-aware dim-2 (eyebrows, hints).
  static Color fgDim2Of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? fgDim2 : fgLightDim2;

  // ─── Pill button (white-on-dark in dark, black-on-cream in light) ────
  static Color btnPillBg(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? Colors.white : const Color(0xFF111111);
  static Color btnPillFg(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? Colors.black : Colors.white;

  // ─── Radii ────────────────────────────────────────────────────────────
  // Matches Lumen Design System tokens. rXl = glass-card corner (28),
  // rLg = album art (18), distinct from the mini-player surface which
  // stays at 22 because that's a different surface in the design.
  static const rPill = 999.0;
  static const rXl = 28.0;
  static const rLg = 18.0;
  static const rMd = 16.0;
  static const rSm = 14.0;
  static const rXs = 12.0;
  static const r2xs = 10.0;

  // ─── Motion ───────────────────────────────────────────────────────────
  static const ease = Cubic(0.215, 0.61, 0.355, 1.0);
  static const easeOut = Cubic(0.16, 1.0, 0.3, 1.0);
  static const dFast = Duration(milliseconds: 180);
  static const dBase = Duration(milliseconds: 260);
  static const dSlow = Duration(milliseconds: 400);

  // ─── Page padding ─────────────────────────────────────────────────────
  static const pagePad = 18.0;
  static const topSafePad = 80.0;
  static const bottomSafePad = 220.0;

  // ─── Tabular numerics for time/duration text ─────────────────────────
  static const tnum = <FontFeature>[
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  // ─── Mood card gradients (Flacko) ────────────────────────────────────
  static const moodSmart = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6B5BFF), accent],
  );
  static const moodFocus = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orbCyan, Color(0xFF6B5BFF)],
  );
  static const moodChill = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blobPink, orbGold],
  );
  static const moodWorkout = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9E5E), blobPink],
  );
  static const moodNight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orbDeep, orbCyan],
  );
  static const moodDiscover = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orbGold, Color(0xFFFF9E5E)],
  );
  static const moodFavorites = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFF6B5BFF)],
  );
}

/// One phase of the time-of-day wallpaper. Each phase is a stage tint
/// + a triplet of blob colors (warm / cool / accent). The wallpaper
/// blends adjacent phases as the hour advances.
class LumenTodPhase {
  const LumenTodPhase({
    required this.key,
    required this.stage,
    required this.warm,
    required this.cool,
    required this.accent,
  });

  final String key;
  final Color stage;
  final Color warm;
  final Color cool;
  final Color accent;

  /// Linear-interpolate between two phases — used at hour boundaries
  /// so the wallpaper doesn't snap colors at 8am / 4pm / etc.
  static LumenTodPhase lerp(LumenTodPhase a, LumenTodPhase b, double t) {
    final tt = t.clamp(0.0, 1.0);
    return LumenTodPhase(
      key: tt < 0.5 ? a.key : b.key,
      stage: Color.lerp(a.stage, b.stage, tt)!,
      warm: Color.lerp(a.warm, b.warm, tt)!,
      cool: Color.lerp(a.cool, b.cool, tt)!,
      accent: Color.lerp(a.accent, b.accent, tt)!,
    );
  }
}

/// Time-of-day phase tables. Dark = night-leaning; Light = airy daytime.
/// Hours are inclusive-start, exclusive-end on a 24-hour clock; the
/// final entry wraps from 22 through 5am.
class LumenTod {
  // Dark phases
  static const dawnDark = LumenTodPhase(
    key: 'dawn',
    stage: Color(0xFF1B1828),
    warm: Color(0xFFFFB8A0),
    cool: Color(0xFFA0B4FF),
    accent: Color(0xFFFFD7B0),
  );
  static const dayDark = LumenTodPhase(
    key: 'day',
    stage: Color(0xFF0F1420),
    warm: Color(0xFFFFE8B0),
    cool: Color(0xFF5BE0FF),
    accent: Color(0xFFB8FFD7),
  );
  static const goldenDark = LumenTodPhase(
    key: 'golden',
    stage: Color(0xFF1F1418),
    warm: Color(0xFFFF9E5E),
    cool: Color(0xFFFF6B9D),
    accent: Color(0xFFFFD36B),
  );
  static const duskDark = LumenTodPhase(
    key: 'dusk',
    stage: Color(0xFF100A1A),
    warm: Color(0xFFFF6B9D),
    cool: Color(0xFF6B5BFF),
    accent: Color(0xFF5BE0FF),
  );
  static const nightDark = LumenTodPhase(
    key: 'night',
    stage: Color(0xFF050507),
    warm: Color(0xFFB8A8FF),
    cool: Color(0xFF2A1F5E),
    accent: Color(0xFFFF7AA8),
  );

  // Light phases — airy, cream-stage, pastel blobs
  static const dawnLight = LumenTodPhase(
    key: 'dawn',
    stage: Color(0xFFFBF1EC),
    warm: Color(0xFFFFD0BC),
    cool: Color(0xFFCFD8FF),
    accent: Color(0xFFFFE3CC),
  );
  static const dayLight = LumenTodPhase(
    key: 'day',
    stage: Color(0xFFF4F6FB),
    warm: Color(0xFFFFF0BC),
    cool: Color(0xFFBEE6FF),
    accent: Color(0xFFD6F5E2),
  );
  static const goldenLight = LumenTodPhase(
    key: 'golden',
    stage: Color(0xFFFBEFE6),
    warm: Color(0xFFFFC9A6),
    cool: Color(0xFFFFB8D0),
    accent: Color(0xFFFFE0A8),
  );
  static const duskLight = LumenTodPhase(
    key: 'dusk',
    stage: Color(0xFFF1ECF8),
    warm: Color(0xFFFFC0D4),
    cool: Color(0xFFCCC0FF),
    accent: Color(0xFFBFE6F5),
  );
  static const nightLight = LumenTodPhase(
    key: 'night',
    stage: Color(0xFFECE9F2),
    warm: Color(0xFFD4CCFF),
    cool: Color(0xFFBCC8F0),
    accent: Color(0xFFFFC8D6),
  );

  /// Phase + blend factor for the current hour. Returns the active
  /// phase, the next phase, and `t` ∈ [0,1] within the active range
  /// so the painter can lerp on hour boundaries (smoother than snapping
  /// at e.g. 16:00 from `day` to `golden`).
  static ({LumenTodPhase a, LumenTodPhase b, double t}) blendFor(
    DateTime now, {
    required Brightness brightness,
  }) {
    final list = brightness == Brightness.dark
        ? const [
            (5, dawnDark), (8, dayDark), (16, goldenDark),
            (19, duskDark), (22, nightDark),
          ]
        : const [
            (5, dawnLight), (8, dayLight), (16, goldenLight),
            (19, duskLight), (22, nightLight),
          ];
    // Hour on the 5..29 timeline so 22..5am wraps cleanly.
    final raw = now.hour + now.minute / 60.0;
    final h = raw < 5 ? raw + 24 : raw;
    for (var i = 0; i < list.length; i++) {
      final start = list[i].$1.toDouble();
      final end = i + 1 < list.length ? list[i + 1].$1.toDouble() : 29.0;
      if (h >= start && h < end) {
        final t = (h - start) / (end - start);
        final a = list[i].$2;
        // The night phase wraps to dawn next morning, otherwise advance
        // the index. The blend `t` here only really kicks in over the
        // last ~30 mins of the active band — kept linear for simplicity.
        final b = i + 1 < list.length ? list[i + 1].$2 : list[0].$2;
        return (a: a, b: b, t: t);
      }
    }
    return (a: list.last.$2, b: list.last.$2, t: 0);
  }

  /// Greeting copy keyed by hour. Uses sentence case per the brand voice.
  static String greetingFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 22) return 'Good evening';
    return 'Good night';
  }

  /// Eyebrow date label — ALL CAPS, used above the greeting.
  static String dateLabel(DateTime now) {
    const days = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY',
      'SATURDAY', 'SUNDAY',
    ];
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class AppTheme {
  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: LumenTokens.accent,
      onPrimary: Colors.black,
      secondary: LumenTokens.orbViolet,
      onSecondary: Colors.black,
      surface: LumenTokens.surfaceBg,
      onSurface: LumenTokens.fgPrimary,
      surfaceContainerHigh: Color(0xFF14141A),
      surfaceContainerHighest: Color(0xFF1A1A22),
      error: Color(0xFFFF6B6B),
      onError: Colors.white,
    );
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: LumenTokens.fgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: LumenTokens.fgPrimary,
        displayColor: LumenTokens.fgPrimary,
        fontFamily: 'SF Pro Display',
      ),
      dividerColor: Colors.white.withValues(alpha: 0.07),
      iconTheme: const IconThemeData(color: LumenTokens.fgPrimary),
      splashFactory: NoSplash.splashFactory,
    );
  }

  static ThemeData light() {
    final scheme = const ColorScheme.light(
      brightness: Brightness.light,
      primary: LumenTokens.accentStrong,
      onPrimary: Colors.white,
      secondary: LumenTokens.orbViolet,
      onSecondary: Colors.white,
      surface: LumenTokens.lightStageBg,
      onSurface: LumenTokens.fgLightPrimary,
      error: Color(0xFFE53E3E),
      onError: Colors.white,
    );
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: LumenTokens.fgLightPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: LumenTokens.fgLightPrimary,
        displayColor: LumenTokens.fgLightPrimary,
        fontFamily: 'SF Pro Display',
      ),
      iconTheme: const IconThemeData(color: LumenTokens.fgLightPrimary),
      splashFactory: NoSplash.splashFactory,
    );
  }
}
