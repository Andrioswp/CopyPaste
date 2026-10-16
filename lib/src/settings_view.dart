import 'package:flutter/material.dart';

import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = GlassTokens.of(context);
    final AppSettings s = widget.state.settings;
    final AppState state = widget.state;

    // Scrollbar outside, scrollbar-disabling configuration inside: this is what
    // keeps the indicator visible on the glass pane.
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
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(6, 0, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
            const SectionLabel(label: 'Горячая клавиша'),
            SettingsRow(
              title: 'Открывать панель',
              subtitle: s.hotkey.needsAccessibility
                  ? 'С Fn — работает через разрешение «Универсальный доступ»'
                  : 'Работает без дополнительных разрешений',
              trailing: _hotkeyRecorder(t, s),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                'Нажми кнопку и введи сочетание. Можно с Fn (например Fn+V) или один Fn. '
                'Учти: одиночный Fn перехватывает действие клавиши «Глобус» из системных настроек.',
                style: PanelText.subtitle(t).copyWith(fontSize: 10.5, color: t.textTertiary),
              ),
            ),
            SettingsRow(
              title: 'Сбросить на стандартное',
              subtitle: '⌘⇧V',
              trailing: _smallButton(
                t,
                label: 'Сбросить',
                onTap: () => state.setSetting('hotkeyReset', true),
              ),
            ),
            const SoftDivider(),
            const SectionLabel(label: 'Поведение'),
            SettingsRow(
              title: 'Вставлять сразу',
              subtitle: 'После выбора элемент отправляется в активное приложение',
              trailing: SoftSwitch(
                value: s.autoPaste,
                onChanged: (bool value) => state.setSetting('autoPaste', value),
              ),
            ),
            SettingsRow(
              title: 'Запускать при входе',
              subtitle: s.launchAtLogin ? 'CopyPaste стартует вместе с системой' : 'Запуск только вручную',
              trailing: SoftSwitch(
                value: s.launchAtLogin,
                onChanged: (bool value) => state.setSetting('launchAtLogin', value),
              ),
            ),
            SettingsRow(
              title: 'Хранить элементов',
              trailing: SoftSegmented<int>(
                compact: true,
                options: const <int, String>{100: '100', 500: '500', 1000: '1000', 100000: '∞'},
                value: s.maxItems,
                onChanged: (int value) => state.setSetting('maxItems', value),
              ),
            ),
            const SoftDivider(),
            const SectionLabel(label: 'Оформление'),
            SettingsRow(
              title: 'Тема панели',
              subtitle: s.appearance == 'light'
                  ? 'Всегда светлая'
                  : s.appearance == 'dark'
                      ? 'Всегда тёмная'
                      : 'Как в системе',
              trailing: SoftSegmented<String>(
                compact: true,
                options: const <String, String>{
                  'system': 'Система',
                  'light': 'Светлая',
                  'dark': 'Тёмная',
                },
                value: s.appearance,
                onChanged: (String value) => state.setSetting('appearance', value),
              ),
            ),
            SettingsRow(
              title: 'Стекло панели',
              subtitle: s.glassStyle == 'glass'
                  ? 'Liquid Glass (macOS 26+)'
                  : s.glassStyle == 'vibrancy'
                      ? 'Классический blur (NSVisualEffectView)'
                      : 'Автоматически: Liquid Glass, если поддерживается',
              trailing: SoftSegmented<String>(
                compact: true,
                options: const <String, String>{'auto': 'Авто', 'glass': 'Glass', 'vibrancy': 'Blur'},
                value: s.glassStyle,
                onChanged: (String value) => state.setSetting('glassStyle', value),
              ),
            ),
            const SoftDivider(),
            const SectionLabel(label: 'Данные и доступ'),
            SettingsRow(
              title: 'Универсальный доступ',
              subtitle: s.accessibility
                  ? 'Разрешение выдано'
                  : 'Нужно для автовставки и сочетаний с Fn',
              trailing: s.accessibility
                  ? Icon(Icons.check_circle_rounded, size: 16, color: t.accent)
                  : _smallButton(
                      t,
                      label: 'Открыть',
                      onTap: state.requestAccessibilityFromUi,
                    ),
            ),
            SettingsRow(
              title: 'Очистить историю',
              subtitle: 'Закреплённые записи останутся',
              trailing: _smallButton(
                t,
                label: 'Очистить',
                destructive: true,
                onTap: state.clearHistory,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Row(
                children: <Widget>[
                  Text('CopyPaste ${s.version}', style: PanelText.subtitle(t).copyWith(fontSize: 10.5)),
                  const Spacer(),
                  _smallButton(t, label: 'Выход', onTap: state.quitApp),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hotkeyRecorder(GlassTokens t, AppSettings s) {
    final bool capturing = widget.state.capturingHotkey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (capturing) {
            widget.state.cancelCapture();
          } else {
            widget.state.beginCapture();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 104,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: capturing
                ? t.accent.withValues(alpha: 0.16)
                : (t.dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: capturing ? t.selectedBorder : t.hairline,
              width: capturing ? 1.2 : 0.8,
            ),
          ),
          child: Text(
            capturing ? 'Нажми…' : s.hotkey.label,
            style: PanelText.mono(t).copyWith(
              color: capturing ? t.accent : t.textPrimary,
              fontSize: capturing ? 11.5 : 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallButton(
    GlassTokens t, {
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return _SmallButton(t: t, label: label, onTap: onTap, destructive: destructive);
  }
}

class _SmallButton extends StatefulWidget {
  const _SmallButton({
    required this.t,
    required this.label,
    required this.onTap,
    required this.destructive,
  });

  final GlassTokens t;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final GlassTokens t = widget.t;
    final Color base = widget.destructive ? const Color(0xFFE5484D) : t.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? base.withValues(alpha: 0.16)
                : (t.dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _hovered ? base.withValues(alpha: 0.45) : t.hairline,
              width: 0.8,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: _hovered ? base : (widget.destructive ? base : t.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
