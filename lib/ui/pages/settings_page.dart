import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/net/mjpeg_server.dart';
import '../../data/net/protocol.dart';
import '../../data/settings.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'home_page.dart' show askCameraName;
import 'page_scaffold.dart';

/// Réglages de l'application.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _batteryFree;

  @override
  void initState() {
    super.initState();
    _checkBattery();
  }

  Future<void> _checkBattery() async {
    final free = await AppScope.read(context).bridge.batteryUnrestricted();
    if (mounted) setState(() => _batteryFree = free);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final t = context.text;
    final isCamera = s.role == DeviceRole.camera;
    return AppPage(
      header: const PageHeader(title: 'Réglages'),
      children: [
        const NoticeArea(),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingRow(
                title: isCamera ? 'Nom de la caméra' : 'Nom de cet écran',
                subtitle: s.deviceName,
                trailing: AppButton(
                  label: 'Renommer',
                  compact: true,
                  onPressed: () async {
                    final name = await askCameraName(context, initial: s.deviceName);
                    if (name != null) await app.rename(name);
                  },
                ),
              ),
              SettingBlock(
                title: 'Rôle de cet appareil',
                subtitle: 'Changer de rôle oublie les appareils appairés.',
                child: Segmented<DeviceRole>(
                  values: app.canBeCamera ? DeviceRole.values : const [DeviceRole.screen],
                  selected: s.role,
                  labelOf: (r) => r == DeviceRole.camera ? 'Caméra' : 'Écran',
                  onSelected: (role) => _changeRole(context, app, role),
                ),
              ),
              SettingBlock(
                title: 'Thème',
                child: Segmented<AppThemeMode>(
                  values: AppThemeMode.values,
                  selected: s.theme,
                  labelOf: (m) => switch (m) {
                    AppThemeMode.auto => 'Auto',
                    AppThemeMode.light => 'Clair',
                    AppThemeMode.dark => 'Sombre',
                  },
                  onSelected: app.setTheme,
                ),
              ),
            ],
          ),
        ),
        if (app.isAndroid) ...[
          const SectionTitle('Arrière-plan'),
          Tile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isCamera)
                  SettingRow(
                    title: 'Alertes en arrière-plan',
                    subtitle: 'Une notification permanente garde sCam relié aux caméras.',
                    trailing: AppSwitch(
                      label: 'Alertes en arrière-plan',
                      value: s.background,
                      onChanged: (v) => app.screen?.setBackground(v),
                    ),
                  ),
                SettingRow(
                  title: 'Économie de batterie',
                  subtitle: _batteryFree == false
                      ? 'Android peut endormir sCam. Choisissez « Non restreinte » (Samsung : Batterie → Non restreinte).'
                      : 'sCam peut tourner en arrière-plan.',
                  trailing: _batteryFree == false
                      ? AppButton(
                          label: 'Autoriser',
                          compact: true,
                          kind: ButtonKind.primary,
                          onPressed: () async {
                            await app.bridge.requestBatteryUnrestricted();
                            await Future<void>.delayed(const Duration(seconds: 2));
                            await _checkBattery();
                          },
                        )
                      : Icon(Icons.check_circle_rounded, color: context.colors.success),
                ),
              ],
            ),
          ),
        ],
        if (isCamera) ...[const SectionTitle('sDash et Home Assistant'), _MjpegTile(app: app)],
        const SectionTitle('Sécurité'),
        Tile(
          child: Text(
            'sCam ne fonctionne que sur le réseau de la maison : rien ne passe par Internet. L\'image et le son '
            'sont chiffrés, et seuls les appareils appairés (code vérifié des deux côtés) peuvent se connecter.',
            style: t.secondary,
          ),
        ),
        if (app.addresses.isNotEmpty) ...[
          const SizedBox(height: Dim.sectionGap),
          Text('Adresse de cet appareil : ${app.addresses.join(', ')}', style: t.caption),
        ],
      ],
    );
  }

  Future<void> _changeRole(BuildContext context, AppController app, DeviceRole role) async {
    if (role == app.settings.role) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(role == DeviceRole.camera ? 'Devenir une caméra ?' : 'Devenir un écran ?'),
        content: const Text('Les appareils appairés seront oubliés : il faudra les appairer de nouveau.'),
        actions: [
          AppButton(label: 'Annuler', compact: true, onPressed: () => Navigator.of(context).pop(false)),
          AppButton(
            label: 'Changer',
            compact: true,
            kind: ButtonKind.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) await app.chooseRole(role);
  }
}

class _MjpegTile extends StatelessWidget {
  const _MjpegTile({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final camera = app.camera;
    final host = app.addresses.isNotEmpty ? app.addresses.first : 'adresse-de-la-caméra';
    final port = camera?.mjpegBoundPort ?? app.network.mjpegPort;
    final url = 'http://$host:$port/video.mjpg';
    final still = 'http://$host:$port/image.jpg';
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            title: 'Flux MJPEG local',
            subtitle: 'Pour afficher l\'image dans sDash ou Home Assistant. Désactivé par défaut.',
            trailing: AppSwitch(
              label: 'Flux MJPEG local',
              value: s.mjpegEnabled,
              onChanged: (v) => camera?.setMjpeg(v),
            ),
          ),
          if (s.mjpegEnabled) ...[
            const SizedBox(height: 6),
            const MessageBanner(
              error: true,
              message:
                  'Ce flux n\'est pas chiffré : protégé par mot de passe, mais lisible par qui espionnerait '
                  'votre Wi-Fi. Le son n\'y passe pas.',
            ),
            const SizedBox(height: 10),
            _CopyRow(label: 'Flux', value: url),
            _CopyRow(label: 'Image fixe', value: still),
            _CopyRow(label: 'Utilisateur', value: mjpegUser),
            _CopyRow(label: 'Mot de passe', value: s.mjpegPassword),
            const SizedBox(height: 6),
            AppButton(
              label: 'Nouveau mot de passe',
              icon: Icons.refresh_rounded,
              onPressed: () => camera?.newMjpegPassword(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.caption),
              SelectableText(value, style: t.body),
            ],
          ),
        ),
        SquareButton(
          icon: Icons.copy_rounded,
          tooltip: 'Copier : $label',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            AppScope.read(context).showNotice('$label copié.');
          },
        ),
      ],
    );
  }
}
