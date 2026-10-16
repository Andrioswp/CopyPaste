import 'package:flutter/material.dart';

/// Fallback accent (macOS system blue) used before the host reports the
/// real `NSColor.controlAccentColor`.
const Color defaultAccent = Color(0xFF0A84FF);

/// Layout constants of the glass panel. The native window reserves
/// [margin] on every edge so the drop shadow has room to fade out.
class PanelMetrics {
  static const double width = 400;

  /// Transparent frame around the card; must stay larger than the shadow
  /// extent, otherwise the window edge clips it into a hard rectangle.
  static const double margin = 48;
  static const double radius = 22;
  static const double rowHeight = 54;
  static const double maxRows = 10;
  static const double headerHeight = 46;
  static const double searchHeight = 44;
  static const double footerHeight = 40;
  static const double sectionLabelHeight = 26;

  /// Floating hover-preview card shown to the right of the glass pane.
  static const double peekWidth = 300;
  static const double peekGap = 12;
}

/// Colours and surfaces of the "liquid glass" panel. Native AppKit renders
/// the actual blur/glass behind the Flutter surface; these tokens only shape
/// what Flutter draws on top of it.
class GlassTokens {
  const GlassTokens({required this.dark, required this.accent});

  final bool dark;
  final Color accent;

  factory GlassTokens.of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GlassTokens(
      dark: theme.brightness == Brightness.dark,
      accent: theme.colorScheme.primary,
    );
  }

  Color get textPrimary =>
      dark ? Colors.white.withValues(alpha: 0.95) : Colors.black.withValues(alpha: 0.88);
  Color get textSecondary =>
      dark ? Colors.white.withValues(alpha: 0.60) : Colors.black.withValues(alpha: 0.50);
  Color get textTertiary =>
      dark ? Colors.white.withValues(alpha: 0.38) : Colors.black.withValues(alpha: 0.32);
  Color get hairline =>
      dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.09);

  /// Outline of the pane itself: a crisper line in dark mode keeps the edge
  /// from dissolving into the translucent fill.
  Color get cardBorder =>
      dark ? Colors.white.withValues(alpha: 0.17) : Colors.black.withValues(alpha: 0.09);
  Color get hairlineStrong =>
      dark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.13);
  Color get hoverFill =>
      dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
  Color get fieldFill =>
      dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.72);
  Color get badgeFill =>
      dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.85);
  /// Soft selection wash — left accent bar carries focus instead of a glow.
  Color get selectedFill => accent.withValues(alpha: dark ? 0.22 : 0.13);
  Color get selectedBorder => accent.withValues(alpha: dark ? 0.28 : 0.22);
  Color get accentText => dark ? accent : accent;

  /// Frosted fill drawn over the blurred backdrop. Light mode is deliberately
  /// milky (like the macOS sidebars) so the pane never turns dark just because
  /// the wallpaper behind it is dark. Dark mode stays almost flat: an even fill
  /// with no visible top-to-bottom shading keeps the edges crisp.
  LinearGradient get sheen => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.white.withValues(alpha: dark ? 0.10 : 0.80),
          Colors.white.withValues(alpha: dark ? 0.08 : 0.66),
        ],
      );

  /// Bright specular wash along the top edge of the pane. Barely present in
  /// dark mode, where a soft highlight only made the edge look smudged.
  LinearGradient get specular => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.white.withValues(alpha: dark ? 0.05 : 0.45),
          Colors.white.withValues(alpha: 0),
        ],
      );

  /// Inner shading at the bottom, which gives the pane a sense of thickness.
  LinearGradient get innerShade => LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[
          Colors.black.withValues(alpha: dark ? 0.08 : 0.05),
          Colors.black.withValues(alpha: 0),
        ],
      );

  Color get topHighlight =>
      Colors.white.withValues(alpha: dark ? 0.18 : 0.85);

  /// Dark mode uses a tight, low shadow: a wide dark halo made the panel look
  /// blurred around the edges instead of sitting flat on the desktop.
  /// [flipped] mirrors the offset for a panel that hangs above the cursor.
  List<BoxShadow> panelShadowFor({required bool flipped}) {
    final double direction = flipped ? -1 : 1;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.34 : 0.30),
        blurRadius: dark ? 14 : 28,
        offset: Offset(0, (dark ? 6 : 12) * direction),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.18 : 0.12),
        blurRadius: dark ? 4 : 8,
        offset: Offset(0, 2 * direction),
      ),
    ];
  }

  List<BoxShadow> get panelShadow => panelShadowFor(flipped: false);
}

/// Text styles used across the panel.
class PanelText {
  static TextStyle title(GlassTokens t) => TextStyle(
        fontSize: 13.5,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: t.textPrimary,
        letterSpacing: -0.1,
      );

  static TextStyle subtitle(GlassTokens t) => TextStyle(
        fontSize: 11.5,
        height: 1.2,
        color: t.textSecondary,
        letterSpacing: 0,
      );

  static TextStyle section(GlassTokens t) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: t.textTertiary,
      );

  static TextStyle header(GlassTokens t) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
        letterSpacing: -0.2,
      );

  static TextStyle mono(GlassTokens t) => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
        letterSpacing: 0.2,
      );

  /// Row title for URLs and code — Menlo/SF Mono if available, else system.
  static TextStyle codeTitle(GlassTokens t) => TextStyle(
        fontSize: 12.5,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: t.textPrimary,
        letterSpacing: -0.15,
        fontFamily: 'Menlo',
        fontFamilyFallback: const <String>['SF Mono', 'Courier', 'monospace'],
      );
}

ThemeData buildPanelTheme({required Brightness brightness, required Color accent}) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(primary: accent, surface: Colors.transparent);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: null,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.25),
      selectionHandleColor: accent,
    ),
  );
}
