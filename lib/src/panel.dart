import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'entry_hit.dart';
import 'host.dart';
import 'models.dart';
import 'settings_view.dart';
import 'state.dart';
import 'theme.dart';
import 'translate.dart';
import 'widgets.dart';

class PanelScreen extends StatefulWidget {
  const PanelScreen({super.key, required this.state, required this.host});

  final AppState state;
  final HostApi host;

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'search');
  final ScrollController _scroll = ScrollController();

  /// When set, the list jumps to the selected row instead of animating there
  /// (used when the panel appears or the order changes).
  bool _instantScroll = false;
  String _lastQuery = '';
  bool _lastFlipped = false;

  /// One shared hover-preview for the whole panel — resizing the native window
  /// per-row was freezing the list.
  OverlayEntry? _peekEntry;
  ClipItem? _peekItem;
  double _peekTop = 0;
  bool _peekGutterOpen = false;
  Timer? _peekHideTimer;
  Timer? _peekShowTimer;
  /// Active selection inside the peek card — keeps it open so the user can copy.
  TextSelection _peekSelection = const TextSelection.collapsed(offset: 0);
  bool _peekPointerDown = false;
  String? _peekTranslation;
  String? _peekTranslateError;
  bool _peekShowTranslation = false;
  bool _peekTranslating = false;
  /// Source text that [_peekTranslation] was produced from.
  String? _peekTranslatedFrom;

  @override
  void initState() {
    super.initState();
    widget.state.showTick.addListener(_onShown);
    widget.state.addListener(_onStateChanged);
    _scroll.addListener(_onScrollWhilePeek);
  }

  @override
  void dispose() {
    widget.state.showTick.removeListener(_onShown);
    widget.state.removeListener(_onStateChanged);
    _scroll.removeListener(_onScrollWhilePeek);
    _tearDownPeek(closeGutter: true);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onShown() {
    _search.clear();
    _tearDownPeek(closeGutter: true);
    if (mounted) _searchFocus.requestFocus();
    // The list may be mirrored (panel above the input field), so re-sync the
    // scroll position once the new layout is in place — instantly, without a
    // visible scroll animation on appearance.
    _instantScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureSelectionVisible();
      _instantScroll = false;
    });
  }

  void _onScrollWhilePeek() {
    if (_peekEntry != null) _dismissPeekOverlay();
  }

  bool _shouldPeek(ClipItem item) {
    if (item.kind == ClipKind.image) {
      return item.blob != null && item.blob!.isNotEmpty;
    }
    final String text = item.preview.trim();
    if (text.isEmpty) return false;
    return text.length > 42 || text.contains('\n');
  }

  void _schedulePeek(ClipItem item, Offset globalOrigin) {
    _peekHideTimer?.cancel();
    _peekShowTimer?.cancel();
    if (!_shouldPeek(item)) {
      _dismissPeekOverlay();
      return;
    }
    // Gutter already open: swap content instantly — no native resize.
    if (_peekGutterOpen) {
      if (_peekItem?.id != item.id) {
        _resetPeekTranslation();
      }
      _peekItem = item;
      _peekTop = globalOrigin.dy;
      _ensurePeekOverlay();
      return;
    }
    _peekShowTimer = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      unawaited(_showPeek(item, globalOrigin.dy));
    });
  }

  void _schedulePeekHide() {
    _peekShowTimer?.cancel();
    _peekHideTimer?.cancel();
    // Stay open while the user is selecting/holding — the system "Copy"
    // bubble sits outside this card and used to dismiss it on mouse exit.
    if (_peekPointerDown || !_peekSelection.isCollapsed) return;
    // Keep the gutter open — only hide the card. Closing the window on every
    // row exit was the main source of jank. A slightly longer delay lets the
    // pointer cross the gap into the selectable peek card.
    _peekHideTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_peekPointerDown || !_peekSelection.isCollapsed) return;
      _dismissPeekOverlay();
    });
  }

  void _keepPeekOpen() {
    _peekHideTimer?.cancel();
    _peekShowTimer?.cancel();
  }

  String _peekOriginalText() {
    final ClipItem? item = _peekItem;
    if (item == null) return '';
    return item.preview.trim();
  }

  /// Text currently shown in the peek body (original or translation), honouring
  /// an active selection when present.
  String _peekActiveText() {
    final String full = _peekShowTranslation && _peekTranslation != null
        ? _peekTranslation!
        : _peekOriginalText();
    if (full.isEmpty) return '';
    if (_peekSelection.isValid && !_peekSelection.isCollapsed) {
      return _peekSelection.textInside(full);
    }
    return full;
  }

  Future<void> _copyPeekText() async {
    final String text = _peekActiveText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _keepPeekOpen();
  }

  void _resetPeekTranslation() {
    _peekTranslation = null;
    _peekTranslateError = null;
    _peekShowTranslation = false;
    _peekTranslating = false;
    _peekTranslatedFrom = null;
  }

  /// Translates in-place via Google Translate and swaps the peek body to the
  /// result. A second tap restores the original.
  Future<void> _translatePeekText() async {
    _keepPeekOpen();
    if (_peekTranslating) return;

    if (_peekShowTranslation) {
      _peekShowTranslation = false;
      _peekSelection = const TextSelection.collapsed(offset: 0);
      _peekEntry?.markNeedsBuild();
      return;
    }

    final String source = _peekOriginalText();
    if (source.isEmpty) return;

    if (_peekTranslation != null && _peekTranslatedFrom == source) {
      _peekShowTranslation = true;
      _peekSelection = const TextSelection.collapsed(offset: 0);
      _peekEntry?.markNeedsBuild();
      return;
    }

    _peekTranslating = true;
    _peekTranslateError = null;
    _peekEntry?.markNeedsBuild();
    try {
      final String translated = await translateWithGoogle(source, target: 'ru');
      if (!mounted || _peekItem == null) return;
      _peekTranslation = translated;
      _peekTranslatedFrom = source;
      _peekShowTranslation = true;
      _peekSelection = const TextSelection.collapsed(offset: 0);
    } catch (_) {
      _peekTranslateError = 'Не удалось перевести. Проверь интернет и попробуй ещё раз.';
      _peekShowTranslation = false;
    } finally {
      _peekTranslating = false;
      if (mounted) _peekEntry?.markNeedsBuild();
    }
  }

  Future<void> _showPeek(ClipItem item, double globalTop) async {
    if (_peekItem?.id != item.id) {
      _resetPeekTranslation();
    }
    _peekItem = item;
    _peekTop = globalTop;
    if (!_peekGutterOpen) {
      _peekGutterOpen = true;
      await widget.host.setPeekVisible(true);
      if (!mounted || _peekItem?.id != item.id) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted || _peekItem?.id != item.id) return;
    }
    _ensurePeekOverlay();
  }

  void _ensurePeekOverlay() {
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null || _peekItem == null) return;
    if (_peekEntry == null) {
      _peekEntry = OverlayEntry(builder: _buildPeekOverlay);
      overlay.insert(_peekEntry!);
    } else {
      _peekEntry!.markNeedsBuild();
    }
  }

  Widget _buildPeekOverlay(BuildContext context) {
    final ClipItem? item = _peekItem;
    if (item == null) return const SizedBox.shrink();
    final GlassTokens t = GlassTokens.of(context);
    final double top =
        _peekTop.clamp(8.0, MediaQuery.sizeOf(context).height - 220);
    return Positioned(
      left: PanelMetrics.margin + PanelMetrics.width + PanelMetrics.peekGap,
      top: top,
      width: PanelMetrics.peekWidth,
      child: MouseRegion(
        onEnter: (_) => _keepPeekOpen(),
        onExit: (_) => _schedulePeekHide(),
        child: Listener(
          onPointerDown: (_) {
            _peekPointerDown = true;
            _keepPeekOpen();
          },
          onPointerUp: (_) => _peekPointerDown = false,
          onPointerCancel: (_) => _peekPointerDown = false,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.dark
                    ? Colors.black.withValues(alpha: 0.82)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.hairlineStrong, width: 0.8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: _peekBody(t, item),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _peekBody(GlassTokens t, ClipItem item) {
    if (item.kind == ClipKind.image && item.blob != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(item.blob!),
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              cacheWidth: 600,
              errorBuilder: (_, _, _) => Text(item.title, style: PanelText.title(t)),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.subtitle, style: PanelText.subtitle(t)),
        ],
      );
    }

    final TextStyle bodyStyle =
        item.shape == ClipShape.code || item.shape == ClipShape.url
            ? PanelText.codeTitle(t).copyWith(fontSize: 12, height: 1.35)
            : PanelText.title(t).copyWith(fontSize: 12.5, height: 1.35);
    final String text = _peekShowTranslation && _peekTranslation != null
        ? _peekTranslation!
        : item.preview.trim();
    final bool hasSelection = !_peekSelection.isCollapsed;
    final String copyLabel = hasSelection ? 'Копировать' : 'Копировать всё';
    final String translateLabel = _peekTranslating
        ? 'Перевожу…'
        : (_peekShowTranslation ? 'Оригинал' : 'Перевести');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _peekShowTranslation
                    ? 'Перевод'
                    : (item.sourceApp.isNotEmpty ? item.sourceApp : 'Превью'),
                style: PanelText.subtitle(t).copyWith(
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _PeekActionButton(
              label: translateLabel,
              doneLabel: translateLabel,
              accent: t.accent,
              foreground: t.textPrimary,
              border: t.hairline,
              fill: t.hoverFill,
              busy: _peekTranslating,
              onPressed: _translatePeekText,
            ),
            const SizedBox(width: 6),
            _PeekActionButton(
              label: copyLabel,
              doneLabel: 'Скопировано',
              accent: t.accent,
              foreground: t.textPrimary,
              border: t.hairline,
              fill: t.hoverFill,
              onPressed: _copyPeekText,
            ),
          ],
        ),
        if (_peekTranslateError != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _peekTranslateError!,
            style: PanelText.subtitle(t).copyWith(
              color: const Color(0xFFE5484D),
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: bodyStyle,
              cursorColor: t.accent,
              // Floating system "Copy" sits outside the card and closes it —
              // use the header button / ⌘C instead.
              contextMenuBuilder: (BuildContext context, EditableTextState state) {
                return const SizedBox.shrink();
              },
              onSelectionChanged: (TextSelection selection, SelectionChangedCause? cause) {
                _peekSelection = selection;
                if (!selection.isCollapsed) _keepPeekOpen();
                _peekEntry?.markNeedsBuild();
              },
            ),
          ),
        ),
      ],
    );
  }

  void _dismissPeekOverlay() {
    _peekEntry?.remove();
    _peekEntry = null;
    _peekItem = null;
    _peekSelection = const TextSelection.collapsed(offset: 0);
    _peekPointerDown = false;
    _resetPeekTranslation();
  }

  void _tearDownPeek({required bool closeGutter}) {
    _peekShowTimer?.cancel();
    _peekHideTimer?.cancel();
    _peekShowTimer = null;
    _peekHideTimer = null;
    _dismissPeekOverlay();
    if (closeGutter && _peekGutterOpen) {
      _peekGutterOpen = false;
      unawaited(widget.host.setPeekVisible(false));
    }
  }

  void _onStateChanged() {
    final AppState state = widget.state;
    final bool layoutChanged = state.query != _lastQuery || state.flipped != _lastFlipped;
    _lastQuery = state.query;
    _lastFlipped = state.flipped;
    widget.state.syncPanelHeight();
    if (state.pointerSelection) {
      // Hover picked the row that is already under the cursor — scrolling here
      // would shift the list and make the highlight jump.
      state.pointerSelection = false;
      return;
    }
    if (layoutChanged) {
      // A new filter or a mirrored layout reorders the list: jump straight to
      // the selected row instead of animating there.
      _instantScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureSelectionVisible();
        _instantScroll = false;
      });
      return;
    }
    _ensureSelectionVisible();
  }

  void _ensureSelectionVisible() {
    final AppState state = widget.state;
    final List<_Entry> entries = _buildEntries(state);
    final int index = entries.indexWhere(
      (_Entry e) => e.item != null && e.index == state.selected,
    );
    if (index < 0 || !_scroll.hasClients) return;
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += entries[i].height;
    }
    final double viewport = _scroll.position.viewportDimension;
    final double current = _scroll.offset;

    void moveTo(double target) {
      final double clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
      if (_instantScroll) {
        _scroll.jumpTo(clamped);
      } else {
        _scroll.animateTo(
          clamped,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    }

    if (offset < current) {
      moveTo(offset);
    } else if (offset + PanelMetrics.rowHeight > current + viewport) {
      moveTo(offset + PanelMetrics.rowHeight - viewport);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final AppState state = widget.state;
    final LogicalKeyboardKey key = event.logicalKey;
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool meta = keyboard.isMetaPressed;

    if (key == LogicalKeyboardKey.escape) {
      if (state.capturingHotkey) {
        state.cancelCapture();
      } else if (state.menuItemId != null) {
        state.closeMenu();
      } else if (state.page == PanelPage.settings) {
        state.closeSettings();
      } else if (state.query.isNotEmpty) {
        _search.clear();
        state.setQuery('');
      } else {
        state.hide();
      }
      return KeyEventResult.handled;
    }

    if (state.page == PanelPage.settings) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        state.closeSettings();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      state.moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      state.moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      state.pasteSelected();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyP) {
      final ClipItem? item = state.selectedItem;
      if (item != null) state.togglePin(item);
      return KeyEventResult.handled;
    }
    if (meta && (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete)) {
      final ClipItem? item = state.selectedItem;
      if (item != null) state.remove(item);
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.comma) {
      state.openSettings();
      return KeyEventResult.handled;
    }
    if (meta) {
      final int? digit = _digitOf(key);
      if (digit != null && digit >= 1) {
        final List<ClipItem> list = state.ordered;
        if (digit <= list.length) {
          state.paste(list[digit - 1]);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  int? _digitOf(LogicalKeyboardKey key) {
    for (int i = 1; i <= 9; i++) {
      if (key.keyId == LogicalKeyboardKey.digit1.keyId + (i - 1)) return i;
    }
    return null;
  }

  List<_Entry> _buildEntries(AppState state) {
    final List<_Entry> entries = <_Entry>[];
    final List<ClipItem> pinned = state.pinned;
    final List<ClipItem> recent = state.recent;
    final String recentLabel = state.query.isEmpty ? 'Недавние' : 'Найдено';

    if (!state.flipped) {
      int index = 0;
      if (pinned.isNotEmpty) {
        entries.add(_Entry.label('Закреплённые', '${pinned.length}'));
        for (final ClipItem item in pinned) {
          entries.add(_Entry.item(item, index++));
        }
      }
      if (recent.isNotEmpty) {
        entries.add(_Entry.label(recentLabel, '${recent.length}'));
        for (final ClipItem item in recent) {
          entries.add(_Entry.item(item, index++));
        }
      }
      return entries;
    }

    // Full mirror: the whole list is flipped, so the pinned group moves to the
    // bottom (where it sits in the normal layout) and each group is reversed
    // inside, keeping the newest entry closest to the input field.
    if (recent.isNotEmpty) {
      entries.add(_Entry.label(recentLabel, '${recent.length}'));
      for (int i = recent.length - 1; i >= 0; i--) {
        entries.add(_Entry.item(recent[i], pinned.length + i));
      }
    }
    if (pinned.isNotEmpty) {
      entries.add(_Entry.label('Закреплённые', '${pinned.length}'));
      for (int i = pinned.length - 1; i >= 0; i--) {
        entries.add(_Entry.item(pinned[i], i));
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = widget.state;
    final GlassTokens t = GlassTokens.of(context);
    final bool showSettings = state.page == PanelPage.settings;

    return Listener(
      onPointerDown: (PointerDownEvent event) => widget.host.logUi(
        'pointer down ${event.localPosition.dx.round()},${event.localPosition.dy.round()}',
      ),
      onPointerUp: (PointerUpEvent event) => widget.host.logUi(
        'pointer up ${event.localPosition.dx.round()},${event.localPosition.dy.round()}',
      ),
      child: GestureDetector(
        // A click on the transparent frame around the card dismisses the panel.
        behavior: HitTestBehavior.opaque,
        onTap: state.hide,
        child: Padding(
          padding: const EdgeInsets.all(PanelMetrics.margin),
          // Pin the glass card to a fixed width on the left so the hover
          // preview can sit in the expanded gutter on the right.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: PanelMetrics.width,
                child: GestureDetector(
          // Absorbs taps that land on the card itself so they do not close it.
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PanelMetrics.radius),
                gradient: t.sheen,
                boxShadow: t.panelShadowFor(flipped: state.flipped),
                border: Border.all(color: t.cardBorder, width: 0.9),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PanelMetrics.radius - 0.8),
                child: Stack(
                  children: <Widget>[
                    // Glass shading sits under the content so text keeps its
                    // contrast; the hairline below is drawn on top.
                    Column(
                      children: state.flipped
                          // Mirrored panel: it hangs above the input field, so
                          // the header and search sit at the bottom, next to
                          // where the text will be pasted.
                          ? <Widget>[
                              if (!showSettings) _footer(t, state),
                              Expanded(
                                child: showSettings
                                    ? SettingsView(state: state)
                                    : _history(t, state),
                              ),
                              if (state.notice != null) _notice(t, state.notice!),
                              if (state.showAxBanner) _axBanner(t, state),
                              if (!showSettings) _searchField(t, state),
                              _header(t, state),
                            ]
                          : <Widget>[
                              _header(t, state),
                              if (!showSettings) _searchField(t, state),
                              if (state.showAxBanner) _axBanner(t, state),
                              if (state.notice != null) _notice(t, state.notice!),
                              Expanded(
                                child: showSettings
                                    ? SettingsView(state: state)
                                    : _history(t, state),
                              ),
                              if (!showSettings) _footer(t, state),
                            ],
                    ),
                    // The glass shading follows the mirrored layout too.
                    Positioned(
                      top: state.flipped ? null : 0,
                      bottom: state.flipped ? 0 : null,
                      left: 0,
                      right: 0,
                      height: 74,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: state.flipped
                                ? t.innerShade
                                : t.specular,
                            borderRadius: BorderRadius.vertical(
                              top: state.flipped
                                  ? Radius.zero
                                  : Radius.circular(PanelMetrics.radius - 1),
                              bottom: state.flipped
                                  ? Radius.circular(PanelMetrics.radius - 1)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: state.flipped ? null : 0,
                      top: state.flipped ? 0 : null,
                      left: 0,
                      right: 0,
                      height: 64,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: state.flipped ? t.specular : t.innerShade,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: state.flipped ? null : 0,
                      bottom: state.flipped ? 0 : null,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 0.9,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                Colors.white.withValues(alpha: 0),
                                t.topHighlight,
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (state.menuItemId != null) _contextMenu(t, state),
                  ],
                ),
              ),
            ),
          ),
                ), // GestureDetector (card)
              ), // SizedBox
            ],
          ), // Row
        ), // Padding
      ), // outer GestureDetector
    ); // Listener
  }

  Widget _header(GlassTokens t, AppState state) {
    return SizedBox(
      height: PanelMetrics.headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
        child: Row(
          children: <Widget>[
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    t.accent.withValues(alpha: 0.95),
                    t.accent.withValues(alpha: 0.62),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.content_paste_rounded, size: 12, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text('CopyPaste', style: PanelText.header(t)),
            const Spacer(),
            if (!state.settings.accessibility)
              SoftIconButton(
                icon: Icons.shield_outlined,
                tooltip: 'Разрешение «Универсальный доступ» не выдано',
                onPressed: state.requestAccessibilityFromUi,
                tint: t.textTertiary,
              ),
            const SupportAuthorButton(),
            const SizedBox(width: 2),
            SoftIconButton(
              icon: state.page == PanelPage.settings ? Icons.check_rounded : Icons.tune_rounded,
              tooltip: state.page == PanelPage.settings ? 'Готово' : 'Настройки',
              onPressed: state.page == PanelPage.settings
                  ? state.closeSettings
                  : state.openSettings,
            ),
            const SizedBox(width: 2),
            SoftIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Закрыть (esc)',
              onPressed: state.hide,
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(GlassTokens t, AppState state) {
    return SizedBox(
      height: PanelMetrics.searchHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: t.fieldFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.hairline, width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.search_rounded, size: 15, color: t.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  autofocus: true,
                  cursorColor: t.accent,
                  cursorHeight: 15,
                  cursorWidth: 1.4,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: t.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: 'Поиск в истории',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: t.textTertiary,
                    ),
                  ),
                  onChanged: state.setQuery,
                  onSubmitted: (_) => state.pasteSelected(),
                ),
              ),
              if (state.query.isNotEmpty)
                SoftIconButton(
                  icon: Icons.cancel_rounded,
                  size: 18,
                  iconSize: 13,
                  tint: t.textTertiary,
                  onPressed: () {
                    _search.clear();
                    state.setQuery('');
                    _searchFocus.requestFocus();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _axBanner(GlassTokens t, AppState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: t.dark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.accent.withValues(alpha: 0.30), width: 0.8),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.touch_app_rounded, size: 14, color: t.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Без «Универсального доступа» автовставка не работает — включи CopyPaste в списке',
                style: TextStyle(fontSize: 11, height: 1.3, color: t.textPrimary),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: state.requestAccessibilityFromUi,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Разрешить',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            SoftIconButton(
              icon: Icons.close_rounded,
              size: 20,
              iconSize: 12,
              tint: t.textTertiary,
              onPressed: state.dismissAxBanner,
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(GlassTokens t, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: t.hoverFill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.hairline, width: 0.8),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 13, color: t.textSecondary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, height: 1.3, color: t.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _history(GlassTokens t, AppState state) {
    final List<_Entry> entries = _buildEntries(state);
    if (entries.isEmpty) return _emptyState(t, state);

    // The Scrollbar must sit *outside* the ScrollConfiguration that disables
    // automatic scrollbars, otherwise it is suppressed together with them.
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          t.dark ? Colors.white.withValues(alpha: 0.32) : Colors.black.withValues(alpha: 0.26),
        ),
        thickness: const WidgetStatePropertyAll<double>(3),
        radius: const Radius.circular(3),
        crossAxisMargin: 2,
        mainAxisMargin: 6,
      ),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        interactive: true,
        child: ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
          child: Listener(
            // Selection follows the pointer position rather than per-row
            // `onEnter` events: a fast mouse sweep skips rows between frames,
            // which made the highlight jump over entries.
            onPointerHover: _handlePointerHover,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(8, 0, 10, 6),
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int i) {
              final _Entry entry = entries[i];
              if (entry.label != null) {
                return SectionLabel(label: entry.label!, trailing: entry.trailing);
              }
              final ClipItem item = entry.item!;
              return ClipTile(
                item: item,
                index: entry.index!,
                selected: entry.index == state.selected,
                onPaste: () => state.paste(item),
                onTogglePin: () => state.togglePin(item),
                onDelete: () => state.remove(item),
                onPeekHover: (Offset globalOrigin) =>
                    _schedulePeek(item, globalOrigin),
                onPeekLeave: _schedulePeekHide,
                onContextMenu: (Offset local) {
                  final RenderBox? box = context.findRenderObject() as RenderBox?;
                  final Offset global = box == null
                      ? local
                      : box.localToGlobal(Offset.zero) +
                          local -
                          const Offset(PanelMetrics.margin, PanelMetrics.margin);
                  state.openMenu(item.id, global.dx, global.dy);
                },
              );
            },
          ),
          ),
        ),
      ),
    );
  }

  /// Picks the row under the cursor from the pointer position. Rows have fixed
  /// heights, so the hit test is exact and cannot skip an entry.
  void _handlePointerHover(PointerHoverEvent event) {
    final AppState state = widget.state;
    final List<_Entry> entries = _buildEntries(state);
    if (entries.isEmpty) return;
    final int? index = selectionIndexAt(
      entryHeights: entries.map((_Entry e) => e.height).toList(growable: false),
      entryIndices: entries.map((_Entry e) => e.index).toList(growable: false),
      localY: event.localPosition.dy,
      scrollOffset: _scroll.hasClients ? _scroll.offset : 0,
    );
    if (index != null && index != state.selected) {
      state.selectFromPointer(index);
    }
  }

  Widget _emptyState(GlassTokens t, AppState state) {
    final bool searching = state.query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: t.badgeFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.hairline, width: 0.8),
              ),
              child: Icon(
                searching ? Icons.search_off_rounded : Icons.content_paste_off_rounded,
                size: 20,
                color: t.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'Ничего не найдено' : 'История пуста',
              style: PanelText.title(t).copyWith(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Попробуй другое слово или очисти поиск'
                  : 'Скопируй что-нибудь — и это появится здесь',
              textAlign: TextAlign.center,
              style: PanelText.subtitle(t),
            ),
            if (!searching) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  KeyCap(label: state.settings.hotkey.label),
                  const SizedBox(width: 6),
                  Text('открыть у курсора', style: PanelText.subtitle(t)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(GlassTokens t, AppState state) {
    return SizedBox(
      height: PanelMetrics.footerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${state.ordered.length} ${_plural(state.ordered.length)}',
                  style: PanelText.subtitle(t).copyWith(fontSize: 11),
                ),
                const SizedBox(width: 8),
                ClearHistoryButton(state: state),
              ],
            ),
            // Key hints live on the right; the FittedBox only guards against a
            // narrower pane and does not scale them at the default width.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  children: <Widget>[
                    KeyCap(label: '↑↓', dim: true),
                    const SizedBox(width: 3),
                    Text('выбрать', style: PanelText.subtitle(t).copyWith(fontSize: 10.5)),
                    const SizedBox(width: 9),
                    KeyCap(label: '⏎', dim: true),
                    const SizedBox(width: 3),
                    Text('вставить', style: PanelText.subtitle(t).copyWith(fontSize: 10.5)),
                    const SizedBox(width: 9),
                    KeyCap(label: 'esc', dim: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _plural(int n) {
    final int mod10 = n % 10;
    final int mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'запись';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'записи';
    return 'записей';
  }

  Widget _contextMenu(GlassTokens t, AppState state) {
    ClipItem? found;
    for (final ClipItem candidate in state.items) {
      if (candidate.id == state.menuItemId) {
        found = candidate;
        break;
      }
    }
    if (found == null) return const SizedBox.shrink();
    final ClipItem item = found;

    const double menuWidth = 208;
    final double maxX = PanelMetrics.width - menuWidth;
    final double left =
        (state.menuX - PanelMetrics.margin).clamp(0.0, maxX < 0 ? 0.0 : maxX);
    final double top = (state.menuY - PanelMetrics.margin).clamp(0.0, 400.0);

    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: state.closeMenu,
            onSecondaryTap: state.closeMenu,
            child: const SizedBox.expand(),
          ),
          Positioned(
            left: left,
            top: top,
            child: Container(
              width: menuWidth,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: t.dark
                    ? Colors.black.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.hairlineStrong, width: 0.8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _MenuItem(
                    icon: Icons.arrow_forward_rounded,
                    label: 'Вставить',
                    onTap: () {
                      state.closeMenu();
                      state.paste(item);
                    },
                  ),
                  _MenuItem(
                    icon: Icons.copy_rounded,
                    label: 'Скопировать в буфер',
                    onTap: () {
                      state.closeMenu();
                      state.copyOnly(item);
                    },
                  ),
                  _MenuItem(
                    icon: item.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                    label: item.pinned ? 'Открепить' : 'Закрепить',
                    shortcut: '⌘P',
                    onTap: () {
                      state.closeMenu();
                      state.togglePin(item);
                    },
                  ),
                  if (item.kind == ClipKind.files || item.blob != null)
                    _MenuItem(
                      icon: Icons.folder_open_rounded,
                      label: 'Показать в Finder',
                      onTap: () {
                        state.closeMenu();
                        state.reveal(item);
                      },
                    ),
                  Container(
                    height: 0.7,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: t.hairline,
                  ),
                  _MenuItem(
                    icon: Icons.delete_outline_rounded,
                    label: 'Удалить',
                    destructive: true,
                    shortcut: '⌘⌫',
                    onTap: () {
                      state.closeMenu();
                      state.remove(item);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Compact action control for the hover-preview card header.
class _PeekActionButton extends StatefulWidget {
  const _PeekActionButton({
    required this.label,
    required this.doneLabel,
    required this.accent,
    required this.foreground,
    required this.border,
    required this.fill,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final String doneLabel;
  final Color accent;
  final Color foreground;
  final Color border;
  final Color fill;
  final VoidCallback onPressed;
  final bool busy;

  @override
  State<_PeekActionButton> createState() => _PeekActionButtonState();
}

class _PeekActionButtonState extends State<_PeekActionButton> {
  bool _hovered = false;
  bool _done = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PeekActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && _done) {
      _reset?.cancel();
      _done = false;
    }
  }

  void _handleTap() {
    if (widget.busy) return;
    widget.onPressed();
    // Skip the flash for busy/toggle actions where label already changes.
    if (widget.doneLabel == widget.label) return;
    setState(() => _done = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _done || widget.busy;
    final Color tint = active
        ? widget.accent
        : (_hovered ? widget.foreground : widget.accent);
    return MouseRegion(
      cursor: widget.busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered || active
                ? widget.accent.withValues(alpha: 0.14)
                : widget.fill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: active ? widget.accent.withValues(alpha: 0.45) : widget.border,
              width: 0.8,
            ),
          ),
          child: Text(
            _done ? widget.doneLabel : widget.label,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: tint,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the CloudTips tip jar in the default browser.
class SupportAuthorButton extends StatefulWidget {
  const SupportAuthorButton({super.key});

  static const String url = 'https://pay.cloudtips.ru/p/0f917dbb';

  @override
  State<SupportAuthorButton> createState() => _SupportAuthorButtonState();
}

class _SupportAuthorButtonState extends State<SupportAuthorButton> {
  bool _hovered = false;

  Future<void> _open() async {
    try {
      await Process.start('open', <String>[SupportAuthorButton.url]);
    } catch (_) {
      // Best-effort: the panel keeps working even if the browser fails to launch.
    }
  }

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final Color tint = _hovered ? t.accent : t.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered ? t.accent.withValues(alpha: t.dark ? 0.22 : 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _hovered ? t.accent.withValues(alpha: 0.35) : t.hairline,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.favorite_rounded, size: 11, color: tint),
              const SizedBox(width: 4),
              Text(
                'Поддержать',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Footer button that clears the history. The first click arms it, the second
/// one clears; pinned entries are always kept.
class ClearHistoryButton extends StatefulWidget {
  const ClearHistoryButton({super.key, required this.state});

  final AppState state;

  @override
  State<ClearHistoryButton> createState() => _ClearHistoryButtonState();
}

class _ClearHistoryButtonState extends State<ClearHistoryButton> {
  static const Duration _armWindow = Duration(seconds: 3);
  static const Color _danger = Color(0xFFE5484D);

  bool _hovered = false;
  bool _armed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (!_armed) {
      setState(() => _armed = true);
      _timer?.cancel();
      _timer = Timer(_armWindow, () {
        if (!mounted) return;
        setState(() => _armed = false);
        _timer = null;
      });
      return;
    }
    _timer?.cancel();
    _timer = null;
    setState(() => _armed = false);
    widget.state.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final Color tint = _armed
        ? _danger
        : (_hovered ? t.textPrimary : t.textTertiary);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _armed
                ? _danger.withValues(alpha: 0.16)
                : (_hovered ? t.hoverFill : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _armed ? _danger.withValues(alpha: 0.45) : t.hairline,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _armed ? Icons.delete_forever_rounded : Icons.delete_sweep_outlined,
                size: 12.5,
                color: tint,
              ),
              const SizedBox(width: 5),
              Text(
                _armed ? 'Точно?' : 'Очистить',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: _armed ? _danger : (_hovered ? t.textPrimary : t.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? shortcut;
  final bool destructive;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final Color color = widget.destructive
        ? const Color(0xFFE5484D)
        : (_hovered ? t.textPrimary : t.textSecondary);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.destructive
                    ? const Color(0xFFE5484D).withValues(alpha: 0.14)
                    : t.hoverFill)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: <Widget>[
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.shortcut != null)
                Text(
                  widget.shortcut!,
                  style: TextStyle(fontSize: 10.5, color: t.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClipTile extends StatefulWidget {
  const ClipTile({
    super.key,
    required this.item,
    required this.index,
    required this.selected,
    required this.onPaste,
    required this.onTogglePin,
    required this.onDelete,
    required this.onPeekHover,
    required this.onPeekLeave,
    required this.onContextMenu,
  });

  final ClipItem item;
  final int index;
  final bool selected;
  final VoidCallback onPaste;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final ValueChanged<Offset> onPeekHover;
  final VoidCallback onPeekLeave;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<ClipTile> createState() => _ClipTileState();
}

class _ClipTileState extends State<ClipTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final ClipItem item = widget.item;
    final bool selected = widget.selected;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          widget.onPeekHover(box.localToGlobal(Offset.zero));
        }
      },
      onExit: (_) {
        widget.onPeekLeave();
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPaste,
        onSecondaryTapDown: (TapDownDetails details) =>
            widget.onContextMenu(details.localPosition),
        child: SizedBox(
          height: PanelMetrics.rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: const Duration(milliseconds: 60),
              // Asymmetric fade: the highlight appears smoothly but disappears
              // quickly, so sweeping the pointer along the list does not leave
              // a trail of half-faded rows behind it.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
                duration: Duration(milliseconds: selected ? 110 : 55),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double highlight, Widget? child) {
                  final Color restingFill =
                      _hovered && !selected ? t.hoverFill : Colors.transparent;
                  final Color fill = _pressed && !selected
                      ? t.hairlineStrong
                      : Color.lerp(restingFill, t.selectedFill, highlight)!;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      children: <Widget>[
                        // Focus cue: accent bar on the leading edge.
                        if (highlight > 0.01)
                          Positioned(
                            left: 3,
                            top: 10,
                            bottom: 10,
                            child: Opacity(
                              opacity: highlight,
                              child: Container(
                                width: 3,
                                decoration: BoxDecoration(
                                  color: t.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(
                            left: 6 + 4 * highlight,
                            right: 6,
                          ),
                          child: child,
                        ),
                      ],
                    ),
                  );
                },
                child: Row(
                  children: <Widget>[
                    ClipBadge(item: item),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            style: item.shape == ClipShape.code ||
                                    item.shape == ClipShape.url ||
                                    item.shape == ClipShape.color
                                ? PanelText.codeTitle(t)
                                : PanelText.title(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2.5),
                          Text(
                            item.subtitle,
                            style: PanelText.subtitle(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 46,
                      child: _hovered || selected
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                SoftIconButton(
                                  icon: item.pinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  size: 20,
                                  iconSize: 12.5,
                                  tint: item.pinned ? t.accent : t.textTertiary,
                                  tooltip: item.pinned ? 'Открепить' : 'Закрепить',
                                  onPressed: widget.onTogglePin,
                                ),
                                SoftIconButton(
                                  icon: Icons.delete_outline_rounded,
                                  size: 20,
                                  iconSize: 13,
                                  tint: t.textTertiary,
                                  tooltip: 'Удалить',
                                  onPressed: widget.onDelete,
                                ),
                              ],
                            )
                          : item.pinned
                              ? Align(
                                  alignment: Alignment.centerRight,
                                  child: Icon(
                                    Icons.push_pin_rounded,
                                    size: 11,
                                    color: t.accent.withValues(alpha: 0.8),
                                  ),
                                )
                              : null,
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

/// Flattened list entry: either a section label or a selectable item.
class _Entry {
  _Entry.label(this.label, this.trailing)
      : item = null,
        index = null;

  _Entry.item(this.item, this.index)
      : label = null,
        trailing = null;

  final String? label;
  final String? trailing;
  final ClipItem? item;
  final int? index;

  double get height => label != null ? PanelMetrics.sectionLabelHeight : PanelMetrics.rowHeight;
}
