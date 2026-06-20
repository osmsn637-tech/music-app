import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        AdaptiveGlass,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;

import '../../features/nav/nav_collapse_controller.dart';
import '../theme/app_theme.dart';

/// Shared liquid-glass tuning for the floating nav surfaces (tab pill +
/// search button) — matches the mini-player so the whole bottom chrome
/// reads as one glass family. `premium` routes through Impeller's native
/// scene graph on iOS so the glass refracts the content behind it (clear)
/// instead of flat-frosting.
const LiquidGlassSettings _navGlass = LiquidGlassSettings(
  blur: 14,
  thickness: 18,
  // Brighter fill + rim than the mini-player so the round search button
  // actually reads against the dark home (it was near-invisible at 8%).
  glassColor: Color(0x33FFFFFF),
  lightIntensity: 0.85,
  glowIntensity: 0.5,
);

/// Single nav-item description. Mirrors the old `TabSpec` shape so call
/// sites compose the same way.
class NavTabSpec {
  const NavTabSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.accent = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool accent;
}

/// Geometry constants for the floating nav. Exposed on a single class
/// so [ExpandingPlayer] can compute its mini rect from the same numbers
/// the nav uses to lay itself out — every measurement that the mini
/// player needs to know about comes from here.
///
/// Most dimensions come in `*Rest` / `*Collapsed` pairs and are lerped
/// by the current nav-collapse value: as the user scrolls down the
/// row, buttons, and mini player all shrink together so the collapsed
/// surface feels lighter than the at-rest one.
class NavGeometry {
  const NavGeometry._();

  /// Horizontal inset from the screen edge.
  static const double hInset = 14;

  /// Bottom inset above the home indicator / safe area.
  static const double bottomInset = 6;

  /// Gap between the at-rest mini player row and the tab/search row.
  static const double rowGap = 8;

  /// Gap between the tab pill and the inline mini-player / search
  /// button when on the collapsed single-row layout.
  static const double inlineGap = 8;

  /// Tab pill / search button row height — at rest and when collapsed.
  static const double rowHeightRest = 60;
  static const double rowHeightCollapsed = 48;

  /// Square side of the search button (and the pill when fully
  /// collapsed) — at rest and when collapsed.
  static const double squareSideRest = 60;
  static const double squareSideCollapsed = 48;

  /// Mini player height when sitting on its own row above the nav
  /// (collapse=0).
  static const double miniRestHeight = 64;

  /// Lerps row height for the current collapse value.
  static double rowHeightAt(double c) =>
      ui.lerpDouble(rowHeightRest, rowHeightCollapsed, c)!;

  /// Lerps the square side for the current collapse value.
  static double squareSideAt(double c) =>
      ui.lerpDouble(squareSideRest, squareSideCollapsed, c)!;
}

/// Apple-Music style floating nav. Renders the tab pill (Home, Flacko,
/// Library) on the left and the search button on the right, both
/// resting at the same baseline. Subscribes to [NavCollapseController]
/// and morphs:
///
///  * At rest (collapse=0): tab pill stretches to fill the row up to
///    the search button — no empty gutter in the middle.
///  * Collapsed (collapse=1): pill shrinks to one slot wide, inactive
///    tabs slide into the active one with fading opacity, leaving room
///    for the inline mini player between pill and search.
///
/// The mini player isn't a child of this widget — it's rendered on top
/// by the home shell's [ExpandingPlayer] which uses the same geometry
/// constants (see [NavGeometry]) so the visual layout stays coherent.
class LiquidNavBar extends StatelessWidget {
  const LiquidNavBar({
    super.key,
    required this.tabs,
    required this.activePillIndex,
    required this.onTabSelected,
    required this.search,
    required this.searchActive,
    required this.onSearch,
    required this.onExpandRequest,
  });

  /// The three pill tabs, in display order: Home, Flacko, Library.
  final List<NavTabSpec> tabs;

  /// Currently active pill slot (0–2), or -1 if the active home-shell
  /// tab is Search (no pill slot highlighted).
  final int activePillIndex;

  /// Fired with the pill slot index when an active or inactive pill
  /// item is tapped. The caller maps slot → tab index.
  final void Function(int slot) onTabSelected;

  /// Search button spec.
  final NavTabSpec search;
  final bool searchActive;
  final VoidCallback onSearch;

  /// Tapping the visible (active) tab while the pill is collapsed
  /// expands the nav back out.
  final VoidCallback onExpandRequest;

  @override
  Widget build(BuildContext context) {
    final nav = NavCollapseScope.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return AnimatedBuilder(
      animation: nav.animation,
      builder: (context, _) {
        final t = nav.value;

        // When no pill slot is active (Search tab), pretend Home is the
        // "anchor" so the collapsed pill still has something coherent to
        // shrink down to. The active styling is suppressed in that case.
        final anchor = activePillIndex < 0 ? 0 : activePillIndex;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            NavGeometry.hInset,
            0,
            NavGeometry.hInset,
            safeBottom + NavGeometry.bottomInset,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _TabPill(
                  tabs: tabs,
                  activePillIndex: activePillIndex,
                  anchorIndex: anchor,
                  collapse: t,
                  onTap: onTabSelected,
                  onExpandRequest: onExpandRequest,
                ),
              ),
              const SizedBox(width: NavGeometry.inlineGap),
              _SearchButton(
                spec: search,
                active: searchActive,
                collapse: t,
                onTap: onSearch,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TabPill extends StatefulWidget {
  const _TabPill({
    required this.tabs,
    required this.activePillIndex,
    required this.anchorIndex,
    required this.collapse,
    required this.onTap,
    required this.onExpandRequest,
  });

  final List<NavTabSpec> tabs;
  final int activePillIndex;
  final int anchorIndex;
  final double collapse;
  final void Function(int slot) onTap;
  final VoidCallback onExpandRequest;

  @override
  State<_TabPill> createState() => _TabPillState();
}

class _TabPillState extends State<_TabPill> {
  /// Lens left-edge while the user is dragging it; null when settled (the
  /// lens then animates to the active tab).
  double? _dragX;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        final squareSide = NavGeometry.squareSideAt(widget.collapse);
        final rowHeight = NavGeometry.rowHeightAt(widget.collapse);
        final pillWidth = ui.lerpDouble(
          fullWidth,
          squareSide,
          widget.collapse,
        )!;
        // Glass paints a 1px hairline border each side → slots sit 2px in.
        const glassBorder = 2.0;
        final slotWidth = (fullWidth - glassBorder) / tabs.length;
        final innerSquare = squareSide - glassBorder;

        final activeIndex = widget.activePillIndex.clamp(0, tabs.length - 1);
        const lensInset = 4.0;
        final lensWidth = slotWidth - lensInset * 2;
        final settledLeft = activeIndex * slotWidth + lensInset;
        final lensLeft = _dragX ?? settledLeft;
        final maxLeft = (tabs.length - 1) * slotWidth + lensInset;

        // The lens is the selector; only meaningful at rest. Fade it as the
        // pill collapses to a single icon while scrolling.
        final lensOpacity = (1 - widget.collapse * 2).clamp(0.0, 1.0);
        final showLens = widget.activePillIndex >= 0 && lensOpacity > 0;

        void onPanStart(DragStartDetails _) {
          setState(() => _dragX = lensLeft);
        }

        void onPanUpdate(DragUpdateDetails d) {
          setState(() {
            _dragX = ((_dragX ?? settledLeft) + d.delta.dx).clamp(
              lensInset,
              maxLeft,
            );
          });
        }

        void onPanEnd(DragEndDetails _) {
          final center = (_dragX ?? settledLeft) + lensWidth / 2;
          final target = (center / slotWidth).floor().clamp(0, tabs.length - 1);
          setState(() => _dragX = null);
          widget.onTap(target);
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: pillWidth,
            height: rowHeight,
            child: AdaptiveGlass(
              shape: LiquidRoundedSuperellipse(borderRadius: LumenTokens.rPill),
              quality: GlassQuality.premium,
              settings: _navGlass,
              // One self-contained compositing layer for the Row + lens,
              // sitting above the outer premium-glass surface — this is what
              // lets the lens BackdropFilter actually sample (and magnify)
              // the sibling icons painted behind it.
              child: RepaintBoundary(
                child: Stack(
                  children: [
                    // Tab icons + labels — sit BEHIND the lens so the lens
                    // magnifies whichever one it's over.
                    Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          _PillSlot(
                            spec: tabs[i],
                            active: i == widget.activePillIndex,
                            isAnchor: i == widget.anchorIndex,
                            expandedWidth: slotWidth,
                            rowHeight: rowHeight,
                            squareSide: innerSquare,
                            collapse: widget.collapse,
                            onTap: () {
                              final isAnchor = i == widget.anchorIndex;
                              if (widget.collapse > 0.5 && isAnchor) {
                                widget.onExpandRequest();
                                return;
                              }
                              widget.onTap(i);
                            },
                          ),
                      ],
                    ),
                    // Draggable magnifier lens = the selector. Drag it between
                    // tabs; it magnifies the tab under it and snaps to the
                    // nearest one on release.
                    if (showLens)
                      AnimatedPositioned(
                        duration: _dragX != null
                            ? Duration.zero
                            : LumenTokens.dBase,
                        curve: LumenTokens.ease,
                        left: lensLeft,
                        top: lensInset,
                        bottom: lensInset,
                        width: lensWidth,
                        child: Opacity(
                          opacity: lensOpacity,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: onPanStart,
                            onPanUpdate: onPanUpdate,
                            onPanEnd: onPanEnd,
                            child: _MagnifierLens(
                              width: lensWidth,
                              height: rowHeight - lensInset * 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Magnifier lens. Magnifies whatever sibling content is painted behind it
/// (the tab icon + label) via a center-anchored matrix [BackdropFilter], with
/// a hairline capsule outline tracing the rim — no fill or shadow, so it reads
/// as a clean lens edge around the icon swelling under it as it's dragged.
///
/// Deliberately NOT wrapped in its own RepaintBoundary — it must share the
/// parent layer so the BackdropFilter can sample the icons behind it.
class _MagnifierLens extends StatelessWidget {
  const _MagnifierLens({required this.width, required this.height});

  final double width;
  final double height;

  // 1.35x reads as a clear lens without melting the small label.
  static const double _scale = 1.35;

  ui.ImageFilter _filter() {
    // Scale [_scale]x about the lens centre. Column-major 4x4 affine:
    // x' = s·x + (1-s)·cx ; y' = s·y + (1-s)·cy. Translation in last column.
    const s = _scale;
    final tx = (1 - s) * (width / 2);
    final ty = (1 - s) * (height / 2);
    final storage = Float64List.fromList(<double>[
      s, 0, 0, 0, // col 0
      0, s, 0, 0, // col 1
      0, 0, 1, 0, // col 2
      tx, ty, 0, 1, // col 3
    ]);
    return ui.ImageFilter.matrix(storage, filterQuality: FilterQuality.high);
  }

  @override
  Widget build(BuildContext context) {
    // Capsule (fully rounded) so the outline reads as a lens rim, never a
    // square. No fill, no shadow — just the magnification plus a hairline
    // outline tracing the puck edge.
    final radius = BorderRadius.circular(height / 2);
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: _filter(),
            child: const SizedBox.expand(),
          ),
        ),
        // Outline only — hairline rim, no fill.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// One tab slot. At collapse=0 each slot is exactly [expandedWidth]
/// wide (so the three slots sum to the full pill width). As collapse
/// approaches 1, inactive slots shrink to 0 width and fade out, while
/// the anchor slot lerps from [expandedWidth] toward [squareSide] —
/// the final collapsed pill width. Icon and label also shrink so the
/// content stays proportionate inside the shorter collapsed row.
class _PillSlot extends StatelessWidget {
  const _PillSlot({
    required this.spec,
    required this.active,
    required this.isAnchor,
    required this.expandedWidth,
    required this.rowHeight,
    required this.squareSide,
    required this.collapse,
    required this.onTap,
  });

  final NavTabSpec spec;
  final bool active;
  final bool isAnchor;
  final double expandedWidth;
  final double rowHeight;
  final double squareSide;
  final double collapse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = isAnchor
        ? ui.lerpDouble(expandedWidth, squareSide, collapse)!
        : ui.lerpDouble(expandedWidth, 0, collapse)!;
    final opacity = isAnchor ? 1.0 : (1.0 - collapse * 1.4).clamp(0.0, 1.0);

    final activeFg = spec.accent ? LumenTokens.accent : LumenTokens.fg(context);
    final inactiveFg = LumenTokens.fgDimOf(context);
    final color = active ? activeFg : inactiveFg;

    final iconSize = ui.lerpDouble(22, 18, collapse)!;
    final labelSize = ui.lerpDouble(10, 9, collapse)!;

    return SizedBox(
      width: width,
      height: rowHeight,
      child: ClipRect(
        child: OverflowBox(
          minWidth: 0,
          maxWidth: expandedWidth,
          alignment: Alignment.center,
          child: Opacity(
            opacity: opacity,
            // Plain tap detector — no Material InkWell, so tapping a tab just
            // moves the magnifier with zero square splash/highlight behind it.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active ? spec.activeIcon : spec.icon,
                      size: iconSize,
                      color: color,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.label,
                      style: TextStyle(
                        fontSize: labelSize,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Search / magnifier button — liquid glass, tappable.
class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.spec,
    required this.active,
    required this.collapse,
    required this.onTap,
  });

  final NavTabSpec spec;
  final bool active;
  final double collapse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Near-white when inactive (not the dim foreground) so it reads on the
    // glass; accent when it's the active tab.
    final color = active
        ? LumenTokens.accent
        : LumenTokens.fg(context).withValues(alpha: 0.92);
    final side = NavGeometry.squareSideAt(collapse);
    final rowHeight = NavGeometry.rowHeightAt(collapse);
    final iconSize = ui.lerpDouble(26, 21, collapse)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: side,
        height: rowHeight,
        child: AdaptiveGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: LumenTokens.rPill),
          quality: GlassQuality.premium,
          settings: _navGlass,
          child: Center(
            child: Icon(
              active ? spec.activeIcon : spec.icon,
              size: iconSize,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
