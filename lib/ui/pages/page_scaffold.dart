import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';

/// Gabarit commun à toutes les pages : en-tête fixe, contenu défilant de largeur limitée.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Dim.contentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(Dim.pagePadding, 14, Dim.pagePadding, 10), child: header),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Dim.pagePadding, 0, Dim.pagePadding, 24),
                    children: children,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// En-tête d'une page secondaire : retour, titre, action facultative.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SquareButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.pageTitle),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// En-tête de la page d'accueil : logo, nom de l'application et de l'appareil, réglages.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.subtitle, this.onSettings});

  final String subtitle;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Row(
      children: [
        Image.asset('assets/branding/logo.png', height: 44, filterQuality: FilterQuality.medium),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('sCam', style: t.pageTitle),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
            ],
          ),
        ),
        if (onSettings != null) SquareButton(icon: Icons.tune_rounded, tooltip: 'Réglages', onPressed: onSettings),
      ],
    );
  }
}

/// Dernier message de l'application (résultat d'une action), s'il y en a un.
class NoticeArea extends StatelessWidget {
  const NoticeArea({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final notice = controller.notice;
    if (notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.gap),
      child: MessageBanner(message: notice.message, error: notice.error, onClose: controller.clearNotice),
    );
  }
}

/// Espace sous une tuile.
class Gap extends StatelessWidget {
  const Gap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Dim.gap),
    child: child,
  );
}
