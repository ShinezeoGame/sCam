import 'package:flutter/material.dart';

import '../../core/detection.dart';
import '../../models/camera.dart';
import '../theme.dart';
import 'controls.dart';
import 'tiles.dart';

/// Heure courte : « 22:41 ».
String shortTime(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// « il y a 3 min », « à 22:41 » au-delà d'une heure.
String ago(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inSeconds < 60) return 'à l\'instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  return 'à ${shortTime(at)}';
}

/// Batterie et température en une ligne : « 82 % · en charge · 31 °C ».
String batteryLine(CameraStatus s) {
  final parts = <String>[
    if (s.battery != null) '${s.battery} %',
    if (s.charging) 'en charge',
    if (s.temperature != null) '${s.temperature!.toStringAsFixed(0)} °C',
    if (s.hot) 'chauffe',
  ];
  return parts.join(' · ');
}

/// Barre de niveau (son ou mouvement), avec le seuil d'alerte marqué d'un trait.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.value, this.threshold, required this.label});

  final double value;
  final double? threshold;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final over = threshold != null && value >= threshold!;
    return Semantics(
      label: label,
      value: '${(value * 100).round()} %',
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(5)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: box.maxWidth * value.clamp(0.0, 1.0),
                decoration: BoxDecoration(color: over ? c.danger : c.accent, borderRadius: BorderRadius.circular(5)),
              ),
              if (threshold != null)
                Positioned(
                  left: (box.maxWidth * threshold!.clamp(0.0, 1.0) - 1.5).clamp(0.0, box.maxWidth - 3),
                  top: -3,
                  bottom: -3,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille d'état : un point coloré et un mot.
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.secondary),
        ),
      ],
    );
  }
}

/// Code d'appairage à comparer, avec les deux réponses possibles.
class PairingCodeTile extends StatelessWidget {
  const PairingCodeTile({
    super.key,
    required this.peerName,
    required this.code,
    required this.onAnswer,
    this.onCamera = false,
  });

  final String peerName;
  final String code;
  final ValueChanged<bool> onAnswer;

  /// Vrai sur la caméra (le texte parle alors de l'écran).
  final bool onCamera;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final spaced = '${code.substring(0, 3)} ${code.substring(3)}';
    return Tile(
      active: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.link_rounded, tone: BadgeTone.onActive),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  onCamera ? '« $peerName » veut regarder cette caméra' : 'Appairage avec « $peerName »',
                  style: t.itemTitle.copyWith(color: c.onActive),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Code de vérification $code',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                spaced,
                textAlign: TextAlign.center,
                style: t.pageTitle.copyWith(fontSize: 40, letterSpacing: 4, color: c.onActive),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            onCamera
                ? 'Vérifiez que le même code s\'affiche sur l\'écran qui demande l\'accès.'
                : 'Vérifiez que le même code s\'affiche sur la caméra, et confirmez des deux côtés.',
            textAlign: TextAlign.center,
            style: t.secondary.copyWith(color: c.onActive),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Refuser', onActive: true, expand: true, onPressed: () => onAnswer(false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'Même code',
                  icon: Icons.check_rounded,
                  kind: ButtonKind.primary,
                  onActive: true,
                  expand: true,
                  onPressed: () => onAnswer(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Réglages d'une caméra : objectif, lampe, qualité, alertes. Utilisé sur la caméra et
/// sur l'écran (les changements partent alors vers la caméra).
class CameraSettingsPanel extends StatelessWidget {
  const CameraSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.hasTorch,
    this.sound,
    this.motion,
  });

  final CameraSettings settings;
  final ValueChanged<CameraSettings> onChanged;
  final bool hasTorch;

  /// Niveaux actuels, pour régler les seuils en connaissance de cause.
  final double? sound;
  final double? motion;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingBlock(
                title: 'Objectif',
                child: Segmented<Lens>(
                  values: Lens.values,
                  selected: settings.lens,
                  labelOf: (l) => l.label,
                  onSelected: (l) => onChanged(settings.copyWith(lens: l)),
                ),
              ),
              SettingRow(
                title: 'Lampe',
                subtitle: hasTorch ? 'Éclaire la pièce pour filmer dans le noir.' : 'Pas de lampe de ce côté.',
                trailing: AppSwitch(
                  label: 'Lampe',
                  value: settings.torch && hasTorch,
                  onChanged: hasTorch ? (v) => onChanged(settings.copyWith(torch: v)) : (_) {},
                ),
              ),
              SettingBlock(
                title: 'Qualité de l\'image',
                subtitle: 'Économe ménage la batterie et le Wi-Fi ; Haute montre plus de détails.',
                child: Segmented<Quality>(
                  values: Quality.values,
                  selected: settings.quality,
                  labelOf: (q) => q.label,
                  onSelected: (q) => onChanged(settings.copyWith(quality: q)),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Alertes'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingRow(
                title: 'Alerte bruit',
                subtitle: 'Des pleurs, une voix : un bruit qui dure plus d\'une seconde.',
                trailing: AppSwitch(
                  label: 'Alerte bruit',
                  value: settings.noiseAlert,
                  onChanged: (v) => onChanged(settings.copyWith(noiseAlert: v)),
                ),
              ),
              if (settings.noiseAlert) ...[
                _ThresholdSlider(
                  label: 'Seuil du bruit',
                  low: 'Bruit fort',
                  high: 'Murmure',
                  // Plus le curseur est à droite, plus le seuil est bas (plus sensible).
                  value: 1 - settings.noiseThreshold,
                  onChanged: (v) => onChanged(settings.copyWith(noiseThreshold: 1 - v)),
                ),
                if (sound != null) ...[
                  Text('Niveau actuel', style: t.caption),
                  const SizedBox(height: 6),
                  LevelMeter(value: sound!, threshold: settings.noiseThreshold, label: 'Niveau sonore'),
                  const SizedBox(height: 10),
                ],
              ],
              SettingRow(
                title: 'Alerte mouvement',
                subtitle: 'Quelqu\'un ou quelque chose bouge dans l\'image.',
                trailing: AppSwitch(
                  label: 'Alerte mouvement',
                  value: settings.motionAlert,
                  onChanged: (v) => onChanged(settings.copyWith(motionAlert: v)),
                ),
              ),
              if (settings.motionAlert) ...[
                _ThresholdSlider(
                  label: 'Sensibilité au mouvement',
                  low: 'Grands gestes',
                  high: 'Moindre détail',
                  value: settings.motionSensitivity,
                  onChanged: (v) => onChanged(settings.copyWith(motionSensitivity: v)),
                ),
                if (motion != null) ...[
                  Text('Mouvement actuel', style: t.caption),
                  const SizedBox(height: 6),
                  LevelMeter(
                    // Échelle dilatée : un mouvement de 25 % de l'image remplit la barre.
                    value: (motion! / 0.25).clamp(0.0, 1.0),
                    threshold: AlertDetector.motionThreshold(settings.motionSensitivity) / 0.25,
                    label: 'Mouvement',
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ThresholdSlider extends StatefulWidget {
  const _ThresholdSlider({
    required this.label,
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String low;
  final String high;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_ThresholdSlider> createState() => _ThresholdSliderState();
}

class _ThresholdSliderState extends State<_ThresholdSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label, style: t.body),
          SizedBox(
            height: 44,
            child: Slider(
              value: (_dragging ?? widget.value).clamp(0.0, 1.0),
              semanticFormatterCallback: (v) => '${(v * 100).round()} %',
              onChanged: (v) => setState(() => _dragging = v),
              // Le réglage n'est envoyé qu'au lâcher du curseur.
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                widget.onChanged(double.parse(v.toStringAsFixed(2)));
              },
            ),
          ),
          Row(
            children: [
              Expanded(child: Text(widget.low, style: t.caption)),
              Expanded(
                child: Text(widget.high, textAlign: TextAlign.end, style: t.caption),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cadre de la vidéo : coins arrondis, fond neutre, 16:9.
class VideoFrame extends StatelessWidget {
  const VideoFrame({super.key, required this.child, this.overlay});

  final Widget child;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Dim.tileRadius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: c.surfaceMuted,
          child: Stack(fit: StackFit.expand, children: [child, ?overlay]),
        ),
      ),
    );
  }
}
