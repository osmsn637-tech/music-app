import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/scale_tap.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'stage_background.dart';

/// Higher-level building blocks layered on top of the raw [Glass]
/// primitive — the pieces every non-home/player screen was missing and
/// fell back to stock Material for. Use these instead of `TextField`,
/// `FilledButton`, `ListTile`, `AlertDialog`, etc. so the whole app
/// speaks the same liquid-glass language as Home and the player.

/// ALL-CAPS section eyebrow. Matches the section markers on Home.
TextStyle glassEyebrow(BuildContext c) => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.6,
  color: LumenTokens.fgDim2Of(c),
);

/// Press-scale wrapper. The design uses no Material ink (splash is
/// `NoSplash` app-wide), so plain `InkWell`s read as dead taps. This
/// gives tactile feedback via a subtle 1.0→0.96 scale instead — use it
/// to wrap any tappable surface (rows, cards, grid tiles). Renders
/// [child] inert when [onTap] is null.
class Pressable extends StatelessWidget {
  const Pressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ScaleTap(onTap: onTap, child: child);
}

/// A titled frosted pane for grouping related rows/controls. The eyebrow
/// title sits *above* the glass (like Home's section headers); [child]
/// is whatever the section holds — usually a `Column` of [GlassRow]s.
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    this.title,
    required this.child,
    this.strong = false,
    this.padding,
  });

  final String? title;
  final Widget child;
  final bool strong;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title!.toUpperCase(), style: glassEyebrow(context)),
          ),
        Glass(
          strong: strong,
          borderRadius: LumenTokens.rXl,
          padding: padding ?? const EdgeInsets.all(6),
          child: child,
        ),
      ],
    );
  }
}

/// Glass pill button. [primary] swaps the frosted pane for the solid
/// high-contrast pill (white-on-dark / black-on-cream) the design uses
/// for the main call-to-action. [destructive] tints it to the error
/// color. Set [expand] to fill the available width.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final error = Theme.of(context).colorScheme.error;
    final Color fg;
    if (primary) {
      fg = destructive ? Colors.white : LumenTokens.btnPillFg(context);
    } else {
      fg = destructive ? error : LumenTokens.fg(context);
    }

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );

    const pad = EdgeInsets.symmetric(horizontal: 18, vertical: 13);
    final Widget inner = primary
        ? Container(
            padding: pad,
            decoration: BoxDecoration(
              color: destructive ? error : LumenTokens.btnPillBg(context),
              borderRadius: BorderRadius.circular(LumenTokens.rPill),
            ),
            child: content,
          )
        : Glass(
            strong: true,
            borderRadius: LumenTokens.rPill,
            padding: pad,
            child: content,
          );

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        child: expand ? SizedBox(width: double.infinity, child: inner) : inner,
      ),
    );
  }
}

/// Round glass icon button — the chrome affordance (back, close, menu,
/// profile). 38px to match the home shell's profile button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 38,
    this.iconSize = 20,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Glass(
        strong: true,
        borderRadius: LumenTokens.rPill,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: color ?? LumenTokens.fg(context),
          ),
        ),
      ),
    );
  }
}

/// Glass-wrapped text input. Drops the Material underline/outline for a
/// frosted pane with a hairline border. Pass [leading]/[trailing] for
/// inline adornments (search icon, clear/send button).
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.leading,
    this.trailing,
    this.borderRadius = LumenTokens.rMd,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? leading;
  final Widget? trailing;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Glass(
      strong: false,
      borderRadius: borderRadius,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            // Swallow the desktop shell's single-key media shortcuts
            // (Space / S / R / L / Q / arrows) while this field is focused, so
            // they reach the caret as normal typing instead of triggering
            // playback. DoNothingAndStopPropagationIntent reports the key
            // unhandled to the framework, which then routes it to text input.
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.space):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.keyS):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.keyR):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.keyL):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.keyQ):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.keyM):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.arrowLeft):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.arrowRight):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
                    DoNothingAndStopPropagationIntent(),
                SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
                    DoNothingAndStopPropagationIntent(),
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                keyboardType: keyboardType,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                cursorColor: LumenTokens.accent,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LumenTokens.fg(context),
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: LumenTokens.fgDim2Of(context),
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Glass row — the [ListTile] replacement. [leading] is any widget
/// (icon, avatar, album art); [trailing] is the affordance/value on the
/// right (chevron, switch, byte count).
class GlassRow extends StatelessWidget {
  const GlassRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.strong = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Glass(
        strong: strong,
        borderRadius: LumenTokens.rMd,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
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

/// Page chassis for pushed routes (settings, sync, playlist detail).
/// Replaces a bare `Scaffold` + Material `AppBar`: paints the drifting
/// [StageBackground] under everything and lays a glass top bar (back
/// button + title + [actions]) above a transparent body.
///
/// [body] supplies its own scrolling and padding — it gets the space
/// below the top bar.
class StageScaffold extends StatelessWidget {
  const StageScaffold({
    super.key,
    this.title,
    this.actions,
    required this.body,
    this.floatingActionButton,
    this.automaticallyImplyLeading = true,
    this.bleedTop = false,
  });

  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final bool automaticallyImplyLeading;

  /// When true the [body] fills behind the status bar and the top bar
  /// floats over it (instead of reserving its own row above the body).
  /// Used by hero pages (album / playlist) so the cover-tinted wash
  /// reaches the very top — no empty band under the status bar.
  final bool bleedTop;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    final topBar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (automaticallyImplyLeading && canPop) ...[
            GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 17,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Text(
                    title!,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: LumenTokens.fg(context),
                    ),
                  ),
          ),
          if (actions != null)
            for (final a in actions!) ...[const SizedBox(width: 8), a],
        ],
      ),
    );

    return StageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        floatingActionButton: floatingActionButton,
        // Transparent Material ancestor so TextFields, taps, and any
        // Material descendants inside [body] resolve correctly even with
        // Glass / BackdropFilter layers between them.
        body: Material(
          type: MaterialType.transparency,
          child: bleedTop
              // Body fills behind the status bar; the top bar floats over
              // it so a hero wash reaches the very top edge.
              ? Stack(
                  children: [
                    Positioned.fill(child: body),
                    SafeArea(bottom: false, child: topBar),
                  ],
                )
              // Default: the top bar reserves its own row above the body.
              : SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      topBar,
                      Expanded(child: body),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Centered glass dialog. Use for confirms, pickers, and edit panels in
/// place of Material's `AlertDialog` / `SimpleDialog`.
Future<T?> showGlassDialog<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 420,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: LumenTokens.dBase,
    pageBuilder: (ctx, _, _) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              type: MaterialType.transparency,
              child: Glass(
                strong: true,
                borderRadius: LumenTokens.rXl,
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final t = LumenTokens.ease.transform(anim.value.clamp(0.0, 1.0));
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      );
    },
  );
}

/// Two-button confirm dialog. Returns true when the user confirms.
/// Mark [destructive] for irreversible actions (clear data, delete).
Future<bool> showGlassConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final res = await showGlassDialog<bool>(
    context,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: LumenTokens.fg(context),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: LumenTokens.fgDimOf(context),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: cancelLabel,
                expand: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                label: confirmLabel,
                primary: true,
                destructive: destructive,
                expand: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Glass bottom sheet. Mirrors `ProfileSheet.show` so every sheet in the
/// app reads as a frosted pane floating off the bottom edge.
Future<T?> showGlassSheet<T>(BuildContext context, {required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Push onto the ROOT navigator so the sheet floats above the home
    // shell's floating nav bar + mini-player. Without this, sheets opened
    // from a song row (inside the inner content navigator) render beneath
    // that chrome and get clipped at the bottom.
    useRootNavigator: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: SafeArea(
        top: false,
        child: Glass(
          strong: true,
          borderRadius: 24,
          padding: const EdgeInsets.all(8),
          child: child,
        ),
      ),
    ),
  );
}
