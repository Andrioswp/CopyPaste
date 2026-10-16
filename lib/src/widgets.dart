import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// Small rounded key hint, e.g. `⏎` or `⌘⇧V`.
class KeyCap extends StatelessWidget {
  const KeyCap({super.key, required this.label, this.dim = false});

  final String label;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: t.badgeFill,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: t.hairline, width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: dim ? t.textTertiary : t.textSecondary,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    return SizedBox(
      height: PanelMetrics.sectionLabelHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: PanelText.section(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null)
              Text(trailing!, style: PanelText.section(t).copyWith(letterSpacing: 0)),
          ],
        ),
      ),
    );
  }
}

/// Square glyph / thumbnail shown at the left of every history row.
class ClipBadge extends StatelessWidget {
  const ClipBadge({super.key, required this.item, this.size = 32});

  final ClipItem item;
  final double size;

  /// Cool blue for links — distinct from the system accent wash on selection.
  static const Color _urlTint = Color(0xFF2F6FED);
  /// Warm slate for shell/code so it does not compete with URL blue.
  static const Color _codeTint = Color(0xFF3D6B5A);
  static const Color _fileTint = Color(0xFF8A6A2F);
  static const Color _imageTint = Color(0xFF7A4FA3);

  /// Avoids repeated `existsSync` syscalls while rows rebuild on hover/scroll.
  static final Map<String, bool> _pathExists = <String, bool>{};

  static bool _exists(String path) =>
      _pathExists.putIfAbsent(path, () => File(path).existsSync());

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final String? thumbPath = _thumbnailPath(item);
    final bool hasThumb = thumbPath != null && _exists(thumbPath);
    final bool hasAppIcon =
        item.sourceIcon.isNotEmpty && _exists(item.sourceIcon);

    if (hasThumb) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.hairline, width: 0.7),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          File(thumbPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          cacheWidth: (size * 2).round(),
          errorBuilder: (_, _, _) =>
              hasAppIcon ? _appIconBadge(t) : _glyphBadge(t),
        ),
      );
    }

    // Prefer the real source-app icon — that's what users scan for.
    if (hasAppIcon) return _appIconBadge(t);

    // Full-bleed colour sample — the badge *is* the swatch.
    if (item.kind != ClipKind.image &&
        item.kind != ClipKind.files &&
        item.shape == ClipShape.color) {
      return _colorBadge(t);
    }

    return _glyphBadge(t);
  }

  Widget _appIconBadge(GlassTokens t) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.hairline, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(item.sourceIcon),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        cacheWidth: (size * 2).round(),
        errorBuilder: (_, _, _) => _glyphBadge(t),
      ),
    );
  }

  static const Set<String> _imageExtensions = <String>{
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.tif', '.tiff',
  };

  /// Images that came from the pasteboard live in the app's blob folder;
  /// copied *files* are referenced by their path on disk.
  static String? _thumbnailPath(ClipItem item) {
    if (item.kind == ClipKind.image) {
      final String? blob = item.blob;
      return (blob != null && blob.isNotEmpty) ? blob : null;
    }
    if (item.kind == ClipKind.files && item.primaryFile.isNotEmpty) {
      final String lower = item.primaryFile.toLowerCase();
      for (final String extension in _imageExtensions) {
        if (lower.endsWith(extension)) return item.primaryFile;
      }
    }
    return null;
  }

  Widget _glyphBadge(GlassTokens t) {
    final ({Color fill, Color ink, IconData icon}) style = _badgeStyle(t);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: style.ink.withValues(alpha: t.dark ? 0.35 : 0.22),
          width: 0.7,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _glyphContent(t, style.icon, style.ink),
    );
  }

  ({Color fill, Color ink, IconData icon}) _badgeStyle(GlassTokens t) {
    if (item.kind == ClipKind.image) {
      return (
        fill: _imageTint.withValues(alpha: t.dark ? 0.28 : 0.14),
        ink: _imageTint,
        icon: Icons.image_rounded,
      );
    }
    if (item.kind == ClipKind.files) {
      return (
        fill: _fileTint.withValues(alpha: t.dark ? 0.28 : 0.14),
        ink: _fileTint,
        icon: Icons.insert_drive_file_rounded,
      );
    }
    switch (item.shape) {
      case ClipShape.url:
        return (
          fill: _urlTint.withValues(alpha: t.dark ? 0.30 : 0.14),
          ink: _urlTint,
          icon: Icons.link_rounded,
        );
      case ClipShape.code:
        return (
          fill: _codeTint.withValues(alpha: t.dark ? 0.30 : 0.14),
          ink: _codeTint,
          icon: Icons.terminal_rounded,
        );
      case ClipShape.color:
        return (
          fill: t.badgeFill,
          ink: t.textSecondary,
          icon: Icons.palette_outlined,
        );
      case ClipShape.plain:
        final bool rich = item.kind == ClipKind.rich;
        return (
          fill: t.badgeFill,
          ink: t.textSecondary,
          icon: rich ? Icons.format_paint_rounded : Icons.notes_rounded,
        );
    }
  }

  Widget _glyphContent(GlassTokens t, IconData icon, Color ink) {
    final double iconSize = item.kind == ClipKind.files && item.fileCount > 1 ? 15 : 16;
    if (item.kind == ClipKind.files && item.fileCount > 1) {
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(icon, size: iconSize, color: ink),
          Positioned(
            right: 2,
            bottom: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${item.fileCount}',
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Center(child: Icon(icon, size: iconSize, color: ink));
  }

  Widget _colorBadge(GlassTokens t) {
    final int? value = parseHexColorValue(item.preview.trim());
    if (value == null) return _glyphBadge(t);
    final Color swatch = Color(value);
    final bool light = swatch.computeLuminance() > 0.72;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: swatch,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: light ? t.hairlineStrong : Colors.black.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
    );
  }
}

/// Round, borderless icon button used in the header and on hovered rows.
class SoftIconButton extends StatefulWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 26,
    this.iconSize = 14,
    this.tint,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? tint;
  final bool selected;

  @override
  State<SoftIconButton> createState() => _SoftIconButtonState();
}

class _SoftIconButtonState extends State<SoftIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final Color color = widget.tint ?? (_hovered || _pressed ? t.textPrimary : t.textSecondary);
    final Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _pressed
                  ? t.hairlineStrong
                  : (_hovered || widget.selected ? t.hoverFill : Colors.transparent),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: color),
          ),
        ),
      ),
    );
    // Hover bubbles are intentionally not rendered: they covered the rows and
    // the buttons are self-explanatory from their icons.
    return button;
  }
}

/// macOS-flavoured switch built on CupertinoSwitch so it matches the system
/// control rather than the Material one.
class SoftSwitch extends StatelessWidget {
  const SoftSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    return Transform.scale(
      scale: 0.82,
      child: CupertinoSwitch(
        value: value,
        activeTrackColor: t.accent,
        onChanged: onChanged,
      ),
    );
  }
}

/// A single row inside the settings page.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: PanelText.title(t)),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: PanelText.subtitle(t),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row),
    );
  }
}

class SoftDivider extends StatelessWidget {
  const SoftDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    return Container(height: 0.7, color: t.hairline);
  }
}

/// Segmented control in the spirit of AppKit's NSSegmentedControl.
class SoftSegmented<T> extends StatelessWidget {
  const SoftSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.fieldFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.hairline, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.entries.map((MapEntry<T, String> entry) {
          final bool active = entry.key == value;
          return GestureDetector(
            onTap: () => onChanged(entry.key),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 3),
                decoration: BoxDecoration(
                  color: active ? t.accent.withValues(alpha: t.dark ? 0.45 : 0.9) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? Colors.white : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
