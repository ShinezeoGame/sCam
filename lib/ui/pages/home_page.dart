import 'package:flutter/material.dart';

import '../../data/net/protocol.dart';
import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'camera_home_page.dart';
import 'page_scaffold.dart';
import 'screen_home_page.dart';

/// Accueil : choix du rôle au premier lancement, puis la page du rôle choisi.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return switch (controller.settings.role) {
      null => const RolePage(),
      DeviceRole.camera => const CameraHomePage(),
      DeviceRole.screen => const ScreenHomePage(),
    };
  }
}

/// Demande le nom d'une caméra (« Chambre de Léo »).
Future<String?> askCameraName(BuildContext context, {String initial = ''}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nom de la caméra'),
      content: TextField(
        controller: field,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Chambre de Léo, Entrée…'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        AppButton(label: 'Annuler', compact: true, onPressed: () => Navigator.of(context).pop()),
        AppButton(
          label: 'Valider',
          compact: true,
          kind: ButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(field.text),
        ),
      ],
    ),
  );
}

/// Premier lancement : cet appareil filme-t-il, ou regarde-t-il ?
class RolePage extends StatelessWidget {
  const RolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final t = context.text;
    return AppPage(
      header: const HomeHeader(subtitle: 'Caméra de surveillance et babyphone'),
      children: [
        const NoticeArea(),
        Text('Que fait cet appareil ?', style: t.sectionTitle),
        const SizedBox(height: 4),
        Text('Vous pourrez changer plus tard dans les réglages.', style: t.secondary),
        const SizedBox(height: 14),
        _RoleTile(
          icon: Icons.videocam_rounded,
          title: 'Caméra',
          text: controller.canBeCamera
              ? 'Ce téléphone, posé et branché, filme et écoute la pièce. Il continue écran éteint.'
              : 'Disponible sur Android seulement : installez sCam sur un téléphone ou une tablette.',
          onTap: controller.canBeCamera
              ? () async {
                  final name = await askCameraName(context);
                  if (name == null || name.trim().isEmpty) return;
                  await controller.rename(name);
                  await controller.chooseRole(DeviceRole.camera);
                }
              : null,
        ),
        const SizedBox(height: Dim.gap),
        _RoleTile(
          icon: Icons.tv_rounded,
          title: 'Écran',
          text: 'Je regarde et j\'écoute mes caméras, et je reçois leurs alertes.',
          onTap: () => controller.chooseRole(DeviceRole.screen),
        ),
        const SizedBox(height: Dim.sectionGap),
        Text(
          'Tout reste sur le Wi-Fi de la maison : rien ne passe par Internet, et seuls les appareils '
          'appairés voient l\'image.',
          style: t.caption,
        ),
      ],
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.icon, required this.title, required this.text, required this.onTap});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: Tile(
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconBadge(icon: icon, tone: BadgeTone.accent, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.itemTitle),
                    const SizedBox(height: 2),
                    Text(text, style: t.secondary),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: context.colors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
