import 'package:flutter/widgets.dart';

import 'app_controller.dart';

/// Rend l'[AppController] accessible dans tout l'arbre de widgets.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  /// Récupère le contrôleur et reconstruit le widget à chaque changement d'état.
  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Récupère le contrôleur sans s'abonner aux changements (pour les actions).
  static AppController read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
