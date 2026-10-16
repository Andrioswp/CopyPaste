import 'dart:async';

import 'package:flutter/material.dart';

import 'src/host.dart';
import 'src/panel.dart';
import 'src/state.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final NativeHost host = NativeHost();
  final AppState state = AppState(host);
  runApp(CopyPasteApp(host: host, state: state));
  unawaited(state.bootstrap());
}

class CopyPasteApp extends StatelessWidget {
  const CopyPasteApp({super.key, required this.host, required this.state});

  final HostApi host;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildPanelTheme(brightness: Brightness.light, accent: defaultAccent),
      home: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, Widget? _) {
          final Brightness brightness =
              state.settings.dark ? Brightness.dark : Brightness.light;
          return Theme(
            data: buildPanelTheme(brightness: brightness, accent: state.accentColor),
            child: Material(
              type: MaterialType.transparency,
              child: PanelScreen(state: state, host: host),
            ),
          );
        },
      ),
    );
  }
}
