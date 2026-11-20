import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../state/screen_controller.dart';
import '../theme.dart';
import '../widgets/camera_widgets.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'camera_home_page.dart' show AlertRow;
import 'live_page.dart';
import 'page_scaffold.dart';
import 'pair_page.dart';
import 'settings_page.dart';

/// Accueil du rôle Écran : les caméras appairées, leur état et les dernières alertes.
class ScreenHomePage extends StatelessWidget {
  const ScreenHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final screen = app.screen;
    final t = context.text;
    final header = HomeHeader(
      subtitle: 'Écran « ${app.settings.deviceName} »',
      onSettings: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
    );
    if (screen == null) {
      return AppPage(
        header: header,
        children: const [Center(child: CircularProgressIndicator())],
      );
    }
    final cameras = screen.cameras;
    final listening = cameras.where((c) => c.session != null && c.listening).toList();
    void openPair() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PairPage()));

    return AppPage(
      header: header,
      children: [
        const NoticeArea(),
        for (final camera in listening)
          Gap(
            child: Tile(
              active: true,
              child: Row(
                children: [
                  const IconBadge(icon: Icons.hearing_rounded, tone: BadgeTone.onActive),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'À l\'écoute : ${camera.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.itemTitle.copyWith(color: context.colors.onActive),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Arrêter',
                    compact: true,
                    onActive: true,
                    onPressed: () => screen.stopWatching(camera.device.id),
                  ),
                ],
              ),
            ),
          ),
        SectionTitle(
          'Caméras',
          detail: cameras.isEmpty ? null : '${cameras.length} appairée${cameras.length > 1 ? 's' : ''}',
        ),
        if (cameras.isEmpty)
          Gap(
            child: EmptyHint(
              icon: Icons.videocam_rounded,
              title: 'Aucune caméra pour l\'instant',
              text: 'Installez sCam sur un téléphone Android, choisissez « Caméra », puis appairez-le ici.',
              action: AppButton(
                label: 'Ajouter une caméra',
                icon: Icons.add_rounded,
                kind: ButtonKind.primary,
                onPressed: openPair,
              ),
            ),
          )
        else ...[
          for (final camera in cameras)
            Gap(
              child: CameraTile(
                camera: camera,
                online: screen.isOnline(camera),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => LivePage(cameraId: camera.device.id))),
              ),
            ),
          AppButton(label: 'Ajouter une caméra', icon: Icons.add_rounded, expand: true, onPressed: openPair),
        ],
        if (screen.alerts.isNotEmpty) ...[
          const SectionTitle('Dernières alertes'),
          Tile(
            child: Column(children: [for (final alert in screen.alerts.take(10)) AlertRow(alert: alert)]),
          ),
        ],
        const SizedBox(height: Dim.sectionGap),
        Text(
          app.isAndroid
              ? 'Les alertes arrivent même quand sCam est en arrière-plan (réglable).'
              : 'Laissez sCam ouvert (même réduit) pour recevoir les alertes.',
          style: t.caption,
        ),
      ],
    );
  }
}

/// Une caméra appairée dans la liste de l'écran.
class CameraTile extends StatelessWidget {
  const CameraTile({super.key, required this.camera, required this.online, required this.onTap});

  final CameraLink camera;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final status = camera.status;
    final (label, color) = !online
        ? (camera.error ?? 'Injoignable pour l\'instant', c.textFaint)
        : (status?.running ?? false)
        ? ('En ligne · filme', c.success)
        : ('En ligne · caméra arrêtée', c.danger);
    final battery = status == null ? '' : batteryLine(status);
    final alert = camera.lastAlert;
    final recentAlert = alert != null && DateTime.now().difference(alert.at) < const Duration(minutes: 5);
    return Tile(
      onTap: onTap,
      active: recentAlert,
      child: Row(
        children: [
          IconBadge(
            icon: Icons.videocam_rounded,
            tone: recentAlert ? BadgeTone.onActive : (online ? BadgeTone.accent : BadgeTone.neutral),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: recentAlert ? TextStyle(color: c.onActive) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    camera.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.itemTitle.copyWith(color: recentAlert ? c.onActive : null),
                  ),
                  const SizedBox(height: 2),
                  if (recentAlert)
                    Text(
                      '${alert.kind.label} ${ago(alert.at)}',
                      style: t.secondary.copyWith(color: c.onActive, fontWeight: FontWeight.w600),
                    )
                  else
                    StatusLabel(text: label, color: color),
                  if (battery.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(battery, style: t.caption.copyWith(color: recentAlert ? c.onActive : null)),
                  ],
                  if (online && (status?.running ?? false)) ...[
                    const SizedBox(height: 8),
                    LevelMeter(
                      value: status!.sound,
                      threshold: status.settings.noiseAlert ? status.settings.noiseThreshold : null,
                      label: 'Niveau sonore',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: recentAlert ? c.onActive : c.textFaint),
        ],
      ),
    );
  }
}
