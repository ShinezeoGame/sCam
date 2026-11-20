import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_scope.dart';
import '../../state/screen_controller.dart';
import '../theme.dart';
import '../widgets/camera_widgets.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

/// Image et son d'une caméra, ses commandes et ses réglages.
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.cameraId});

  final String cameraId;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  ScreenController? _screen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_screen == null) {
      _screen = AppScope.read(context).screen;
      _screen?.watch(widget.cameraId);
    }
  }

  @override
  void dispose() {
    _screen?.leave(widget.cameraId);
    super.dispose();
  }

  void _fullScreen(CameraLink camera) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _FullScreen(cameraId: camera.device.id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final screen = app.screen;
    final camera = screen?.camera(widget.cameraId);
    final t = context.text;
    final c = context.colors;
    if (screen == null || camera == null) {
      return const AppPage(
        header: PageHeader(title: 'Caméra'),
        children: [],
      );
    }
    final online = screen.isOnline(camera);
    final status = camera.status;
    final session = camera.session;

    // Retente de regarder quand la caméra redevient joignable.
    if (online && session == null && (status?.running ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && screen.camera(widget.cameraId)?.session == null) screen.watch(widget.cameraId);
      });
    }

    final String? waiting = !online
        ? (camera.error ?? 'Caméra injoignable. sCam réessaie…')
        : (status != null && !status.running)
        ? 'La caméra est arrêtée. Touchez « Démarrer » sur le téléphone caméra.'
        : null;

    return AppPage(
      header: PageHeader(title: camera.name),
      children: [
        const NoticeArea(),
        VideoFrame(
          child: session != null && waiting == null
              ? ValueListenableBuilder<bool>(
                  valueListenable: session.connected,
                  builder: (context, connected, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTap: () => _fullScreen(camera),
                        child: session.view(brighten: camera.brighten),
                      ),
                      if (!connected) const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: waiting == null
                        ? const CircularProgressIndicator()
                        : Text(waiting, textAlign: TextAlign.center, style: t.secondary),
                  ),
                ),
        ),
        const SizedBox(height: Dim.gap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ToggleChip(
              icon: camera.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: camera.muted ? 'Son coupé' : 'Son',
              selected: !camera.muted,
              onTap: () => screen.setMuted(camera.device.id, !camera.muted),
            ),
            _ToggleChip(
              icon: Icons.nightlight_round,
              label: 'Éclaircir',
              selected: camera.brighten,
              onTap: () => screen.setBrighten(camera.device.id, !camera.brighten),
            ),
            if (status != null && status.hasTorch)
              _ToggleChip(
                icon: status.settings.torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                label: 'Lampe',
                selected: status.settings.torch,
                onTap: () =>
                    screen.configure(camera.device.id, status.settings.copyWith(torch: !status.settings.torch)),
              ),
            _ToggleChip(
              icon: Icons.fullscreen_rounded,
              label: 'Plein écran',
              selected: false,
              onTap: session == null ? null : () => _fullScreen(camera),
            ),
          ],
        ),
        const SizedBox(height: Dim.gap),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (status != null) ...[
                StatusLabel(
                  text: online ? (status.running ? 'En direct' : 'Caméra arrêtée') : 'Injoignable',
                  color: online && status.running ? c.success : c.textFaint,
                ),
                if (batteryLine(status).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Batterie de la caméra : ${batteryLine(status)}', style: t.caption),
                ],
                const SizedBox(height: 4),
              ],
              SettingRow(
                title: 'Écouter en arrière-plan',
                subtitle: app.isAndroid
                    ? 'Le son continue en quittant cette page ou l\'application (babyphone).'
                    : 'Le son continue en quittant cette page.',
                trailing: AppSwitch(
                  label: 'Écouter en arrière-plan',
                  value: camera.listening,
                  onChanged: (v) => screen.setListening(camera.device.id, v),
                ),
              ),
            ],
          ),
        ),
        if (status != null && online) ...[
          const SectionTitle('Réglages de la caméra'),
          CameraSettingsPanel(
            settings: status.settings,
            hasTorch: status.hasTorch,
            canSwitchLens: status.canSwitchLens,
            canRecord: status.canRecord,
            sound: status.running ? status.sound : null,
            motion: status.running ? status.motion : null,
            onChanged: (next) => screen.configure(camera.device.id, next),
          ),
        ],
        if (online && (camera.clips.isNotEmpty || (status?.recording ?? false))) ...[
          SectionTitle('Extraits', detail: status?.recording ?? false ? 'enregistrement en cours' : null),
          if (camera.clips.isEmpty)
            Tile(child: Text('Le premier extrait sera prêt dans quelques secondes.', style: t.secondary))
          else
            Tile(
              child: Column(
                children: [
                  for (final clip in camera.clips)
                    ClipRow(
                      clip: clip,
                      progress: camera.downloads[clip.id],
                      onDownload: () => screen.download(camera.device.id, clip),
                      onOpen: camera.saved.containsKey(clip.id) && (app.isAndroid || app.isWindows)
                          ? () => screen.openClip(camera.device.id, clip.id)
                          : null,
                      onDelete: () => screen.deleteClip(camera.device.id, clip.id),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: Dim.sectionGap),
        AppButton(
          label: 'Oublier cette caméra',
          icon: Icons.link_off_rounded,
          expand: true,
          onPressed: () => _confirmForget(context, screen, camera),
        ),
      ],
    );
  }

  Future<void> _confirmForget(BuildContext context, ScreenController screen, CameraLink camera) async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Oublier « ${camera.name} » ?'),
        content: const Text('Pour la revoir, il faudra l\'appairer de nouveau.'),
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
    if (ok != true) return;
    _screen = null;
    await screen.forget(camera.device.id);
    navigator.pop();
  }
}

/// Bouton bascule à icône et libellé.
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final fg = selected ? c.onAccent : c.text;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: selected ? c.accent : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dim.buttonRadius),
            side: selected ? BorderSide.none : BorderSide(color: c.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 6),
                  Text(label, style: t.button.copyWith(fontSize: 14, color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Image en plein écran : un geste ou le bouton « Retour » referme.
class _FullScreen extends StatefulWidget {
  const _FullScreen({required this.cameraId});

  final String cameraId;

  @override
  State<_FullScreen> createState() => _FullScreenState();
}

class _FullScreenState extends State<_FullScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = AppScope.of(context).screen?.camera(widget.cameraId);
    final session = camera?.session;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (session != null)
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: session.view(brighten: camera!.brighten),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SquareButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Quitter le plein écran',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
