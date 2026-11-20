import 'package:flutter/material.dart';

import '../../models/camera.dart';
import '../../state/app_scope.dart';
import '../../state/camera_controller.dart';
import '../theme.dart';
import '../widgets/camera_widgets.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';
import 'settings_page.dart';

/// Accueil du rôle Caméra : ce que filme l'appareil, qui regarde, les réglages.
class CameraHomePage extends StatefulWidget {
  const CameraHomePage({super.key});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage> {
  bool _preview = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final camera = app.camera;
    final t = context.text;
    final c = context.colors;
    if (camera == null) {
      return AppPage(
        header: HomeHeader(subtitle: 'Caméra « ${app.settings.deviceName} »'),
        children: const [Center(child: CircularProgressIndicator())],
      );
    }
    final pending = camera.pendingPairing;
    final screens = app.settings.paired.values.toList()..sort((a, b) => a.name.compareTo(b.name));

    return AppPage(
      header: HomeHeader(
        subtitle: 'Caméra « ${app.settings.deviceName} »',
        onSettings: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
      ),
      children: [
        const NoticeArea(),
        if (camera.error != null) Gap(child: MessageBanner(message: camera.error!, error: true)),
        if (pending != null)
          Gap(
            child: PairingCodeTile(
              peerName: pending.peerName,
              code: pending.code,
              onCamera: true,
              onAnswer: pending.answer,
            ),
          ),
        VideoFrame(
          child: camera.running && _preview
              ? camera.media.preview()
              : Center(
                  child: Icon(
                    camera.running ? Icons.visibility_off_rounded : Icons.videocam_off_rounded,
                    size: 40,
                    color: c.textFaint,
                  ),
                ),
        ),
        const SizedBox(height: Dim.gap),
        _StatusTile(camera: camera, preview: _preview, onPreview: (v) => setState(() => _preview = v)),
        SectionTitle(
          'Écrans appairés',
          detail: screens.isEmpty ? null : '${camera.viewers} regarde${camera.viewers > 1 ? 'nt' : ''}',
        ),
        if (screens.isEmpty)
          const Gap(
            child: EmptyHint(
              icon: Icons.tv_rounded,
              title: 'Aucun écran pour l\'instant',
              text: 'Touchez « Appairer un écran », puis ajoutez cette caméra depuis sCam sur votre téléphone ou votre PC.',
            ),
          )
        else
          for (final screen in screens)
            Gap(
              child: _ScreenTile(
                name: screen.name,
                connection: camera.connections.where((c) => c.device.id == screen.id).firstOrNull,
                onForget: () => _confirmForget(context, camera, screen.id, screen.name),
              ),
            ),
        _PairingButton(camera: camera),
        const SectionTitle('Réglages de la caméra'),
        CameraSettingsPanel(
          settings: camera.cameraSettings,
          hasTorch: camera.media.hasTorch,
          sound: camera.running ? camera.measures.sound : null,
          motion: camera.running ? camera.measures.motion : null,
          onChanged: camera.updateCameraSettings,
        ),
        if (camera.alerts.isNotEmpty) ...[
          const SectionTitle('Alertes envoyées'),
          Tile(
            child: Column(
              children: [for (final alert in camera.alerts.take(8)) _AlertRow(alert: alert, showCamera: false)],
            ),
          ),
        ],
        const SizedBox(height: Dim.sectionGap),
        Text(
          'Vous pouvez éteindre l\'écran : sCam continue de filmer et d\'écouter. Laissez le téléphone branché.',
          style: t.caption,
        ),
      ],
    );
  }

  Future<void> _confirmForget(BuildContext context, CameraController camera, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Oublier « $name » ?'),
        content: const Text('Cet écran ne pourra plus regarder cette caméra sans un nouvel appairage.'),
        actions: [
          AppButton(label: 'Annuler', compact: true, onPressed: () => Navigator.of(context).pop(false)),
          AppButton(
            label: 'Oublier',
            compact: true,
            kind: ButtonKind.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) await camera.forget(id);
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.camera, required this.preview, required this.onPreview});

  final CameraController camera;
  final bool preview;
  final ValueChanged<bool> onPreview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final status = camera.status;
    final viewers = camera.viewers;
    final state = camera.running
        ? (viewers == 0 ? 'Filme · personne ne regarde' : 'Filme · $viewers écran${viewers > 1 ? 's' : ''}')
        : (camera.starting ? 'Démarrage…' : 'Arrêtée');
    final battery = batteryLine(status);
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusLabel(text: state, color: camera.running ? c.success : c.textFaint),
                    if (battery.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(battery, style: t.caption.copyWith(color: status.hot ? c.danger : null)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                label: camera.running ? 'Arrêter' : 'Démarrer',
                icon: camera.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                kind: camera.running ? ButtonKind.secondary : ButtonKind.primary,
                busy: camera.starting,
                compact: true,
                onPressed: camera.running ? camera.stopCamera : camera.startCamera,
              ),
            ],
          ),
          if (camera.running) ...[
            const SizedBox(height: 14),
            Text('Son', style: t.caption),
            const SizedBox(height: 6),
            LevelMeter(
              value: camera.measures.sound,
              threshold: camera.cameraSettings.noiseAlert ? camera.cameraSettings.noiseThreshold : null,
              label: 'Niveau sonore',
            ),
            const SizedBox(height: 4),
            SettingRow(
              title: 'Aperçu sur cet écran',
              subtitle: 'Le couper ménage la batterie ; la caméra continue.',
              trailing: AppSwitch(label: 'Aperçu', value: preview, onChanged: onPreview),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScreenTile extends StatelessWidget {
  const _ScreenTile({required this.name, required this.connection, required this.onForget});

  final String name;
  final ScreenConnection? connection;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final watching = connection?.watching ?? false;
    final state = connection == null ? 'Hors ligne' : (watching ? 'Regarde en ce moment' : 'Relié, reçoit les alertes');
    return Tile(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          IconBadge(
            icon: watching ? Icons.visibility_rounded : Icons.devices_rounded,
            tone: watching ? BadgeTone.accent : BadgeTone.neutral,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.itemTitle),
                StatusLabel(text: state, color: connection == null ? c.textFaint : c.success),
              ],
            ),
          ),
          SquareButton(icon: Icons.link_off_rounded, tooltip: 'Oublier cet écran', onPressed: onForget),
        ],
      ),
    );
  }
}

class _PairingButton extends StatelessWidget {
  const _PairingButton({required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    if (!camera.pairingOpen) {
      return AppButton(
        label: 'Appairer un écran',
        icon: Icons.add_link_rounded,
        expand: true,
        onPressed: camera.openPairing,
      );
    }
    final left = camera.pairingUntil!.difference(DateTime.now());
    final minutes = left.inMinutes, seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Tile(
      child: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appairage ouvert · $minutes:$seconds', style: t.itemTitle),
                Text('Sur l\'écran, ouvrez sCam et touchez « Ajouter une caméra ».', style: t.secondary),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppButton(label: 'Fermer', compact: true, onPressed: camera.closePairing),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, this.showCamera = true});

  final CameraAlert alert;
  final bool showCamera;

  @override
  Widget build(BuildContext context) => AlertRow(alert: alert, showCamera: showCamera);
}

/// Une alerte dans une liste : genre, caméra, heure.
class AlertRow extends StatelessWidget {
  const AlertRow({super.key, required this.alert, this.showCamera = true});

  final CameraAlert alert;
  final bool showCamera;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            alert.kind == AlertKind.noise ? Icons.graphic_eq_rounded : Icons.directions_run_rounded,
            size: 20,
            color: c.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              showCamera ? '${alert.kind.label} · ${alert.cameraName}' : alert.kind.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.body,
            ),
          ),
          const SizedBox(width: 8),
          Text(shortTime(alert.at), style: t.caption),
        ],
      ),
    );
  }
}
