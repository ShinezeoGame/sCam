import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/settings.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';

class SCamApp extends StatefulWidget {
  const SCamApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<SCamApp> createState() => _SCamAppState();
}

class _SCamAppState extends State<SCamApp> {
  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  late AppThemeMode _mode = widget.controller.settings.theme;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// L'application entière n'est reconstruite que si le thème choisi change.
  void _onControllerChanged() {
    final mode = widget.controller.settings.theme;
    if (mode != _mode) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        title: 'sCam',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: switch (_mode) {
          AppThemeMode.auto => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomePage(),
      ),
    );
  }
}
