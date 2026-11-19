import '../models/camera.dart';

/// Décide quand lever une alerte à partir des mesures de la caméra.
///
/// * Bruit : le niveau doit dépasser le seuil pendant au moins [noiseSustain] sur une
///   fenêtre glissante de [noiseWindow] (des pleurs, pas une porte qui claque).
/// * Mouvement : la part de l'image qui change doit dépasser un seuil tiré de la
///   sensibilité, sur deux mesures de suite (un reflet isolé n'alerte pas).
///
/// Après une alerte, le même genre d'alerte se tait pendant [cooldown].
class AlertDetector {
  AlertDetector({
    this.noiseWindow = const Duration(seconds: 3),
    this.noiseSustain = const Duration(milliseconds: 1200),
    this.cooldown = const Duration(seconds: 30),
  });

  final Duration noiseWindow;
  final Duration noiseSustain;
  final Duration cooldown;

  final _loud = <(DateTime, Duration)>[];
  DateTime? _lastSample;
  int _motionStreak = 0;
  final _lastAlert = <AlertKind, DateTime>{};

  /// Seuil de mouvement (part de l'image) pour une sensibilité donnée : de 25 % de l'image
  /// (sensibilité 0) à 1 % (sensibilité 1).
  static double motionThreshold(double sensitivity) => 0.25 - 0.24 * sensitivity.clamp(0.0, 1.0);

  /// Prend en compte une mesure ; renvoie les alertes à lever.
  List<AlertKind> sample({
    required DateTime at,
    required double sound,
    required double motion,
    required CameraSettings settings,
  }) {
    final alerts = <AlertKind>[];
    final previous = _lastSample;
    _lastSample = at;
    final step = previous == null ? Duration.zero : at.difference(previous);

    if (settings.noiseAlert) {
      if (sound >= settings.noiseThreshold && step > Duration.zero && step < const Duration(seconds: 2)) {
        _loud.add((at, step));
      }
      _loud.removeWhere((entry) => at.difference(entry.$1) > noiseWindow);
      final loudFor = _loud.fold(Duration.zero, (sum, entry) => sum + entry.$2);
      if (loudFor >= noiseSustain && _ready(AlertKind.noise, at)) {
        alerts.add(AlertKind.noise);
        _loud.clear();
      }
    } else {
      _loud.clear();
    }

    if (settings.motionAlert && motion >= motionThreshold(settings.motionSensitivity)) {
      _motionStreak++;
      if (_motionStreak >= 2 && _ready(AlertKind.motion, at)) {
        alerts.add(AlertKind.motion);
        _motionStreak = 0;
      }
    } else {
      _motionStreak = 0;
    }
    return alerts;
  }

  bool _ready(AlertKind kind, DateTime at) {
    final last = _lastAlert[kind];
    if (last != null && at.difference(last) < cooldown) return false;
    _lastAlert[kind] = at;
    return true;
  }

  void reset() {
    _loud.clear();
    _lastSample = null;
    _motionStreak = 0;
  }
}
