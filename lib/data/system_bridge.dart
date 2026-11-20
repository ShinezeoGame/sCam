import 'dart:io';

import 'package:flutter/services.dart';

/// État de la batterie de la caméra.
class BatteryInfo {
  const BatteryInfo({this.level, this.charging = false, this.temperature, this.hot = false});

  final int? level;
  final bool charging;
  final double? temperature;

  /// Le système signale une surchauffe (Android 10 et plus).
  final bool hot;
}

/// Mesures brutes faites par le code Android (`CameraAnalyzer.kt`).
class RawMeasures {
  const RawMeasures({required this.soundDb, required this.motion});

  /// Niveau sonore, en décibels pleine échelle (−90 à 0).
  final double soundDb;

  /// Part de l'image qui a changé, de 0 à 1.
  final double motion;
}

/// Mode du service au premier plan d'Android.
enum ServiceMode {
  /// La caméra filme et écoute, écran éteint.
  camera,

  /// L'écran surveille les alertes (et joue le son) en arrière-plan.
  screen,
}

/// Fonctions propres au système (canal `scam/systeme`, `MainActivity.kt` sur Android,
/// `flutter_window.cpp` sur Windows). Ailleurs, et dans les tests, chaque appel renvoie
/// une valeur neutre.
class SystemBridge {
  const SystemBridge();

  static const _channel = MethodChannel('scam/systeme');

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Nom donné au téléphone par son propriétaire, à défaut son modèle ; le nom de
  /// l'ordinateur sous Windows.
  Future<String> deviceName() async {
    final name = await _call<String>('nomAppareil');
    if (name != null && name.trim().isNotEmpty) return name.trim();
    try {
      return Platform.localHostname;
    } on Object {
      return 'Appareil';
    }
  }

  /// Android filtre la multidiffusion pour économiser la batterie ; ce verrou la laisse passer.
  Future<void> setMulticastLock(bool enabled) => _call<void>('verrouMultidiffusion', enabled);

  /// Demande les autorisations nécessaires ; vrai si elles sont toutes accordées.
  Future<bool> requestPermissions({required bool camera}) async =>
      await _call<bool>('autorisations', {'camera': camera}) ?? true;

  /// Démarre (ou met à jour) le service au premier plan, avec sa notification permanente.
  Future<void> startService(ServiceMode mode, {required String title, required String text}) =>
      _call<void>('serviceDemarrer', {'mode': mode.name, 'titre': title, 'texte': text});

  Future<void> stopService() => _call<void>('serviceArreter');

  Future<BatteryInfo> battery() async {
    final raw = await _call<Map<Object?, Object?>>('batterie');
    if (raw == null) return const BatteryInfo();
    final level = raw['niveau'], temperature = raw['temperature'];
    return BatteryInfo(
      level: level is int && level >= 0 ? level : null,
      charging: raw['enCharge'] == true,
      temperature: temperature is num ? temperature.toDouble() : null,
      hot: raw['chaud'] == true,
    );
  }

  Future<void> startAnalysis({String? videoTrackId, String? audioTrackId}) =>
      _call<void>('analyseDemarrer', {'video': videoTrackId, 'audio': audioTrackId});

  Future<void> stopAnalysis() => _call<void>('analyseArreter');

  Future<RawMeasures?> measure() async {
    final raw = await _call<Map<Object?, Object?>>('analyseMesure');
    if (raw == null) return null;
    final sound = raw['sonDb'], motion = raw['mouvement'];
    return RawMeasures(
      soundDb: sound is num ? sound.toDouble() : -90,
      motion: motion is num ? motion.toDouble().clamp(0.0, 1.0) : 0,
    );
  }

  /// Dernière image de la caméra en JPEG (préparée à la demande, deux fois par seconde au plus).
  Future<Uint8List?> latestJpeg() => _call<Uint8List>('analyseJpeg');

  /// Notification d'alerte (Android) ; sous Windows, la fenêtre clignote dans la barre des tâches.
  Future<void> notifyAlert({required String title, required String text}) =>
      _call<void>('alerte', {'titre': title, 'texte': text});

  /// Vrai si l'économie de batterie d'Android laisse sCam tourner en arrière-plan.
  Future<bool> batteryUnrestricted() async => await _call<bool>('sansRestrictionBatterie') ?? true;

  /// Ouvre la demande du système pour retirer sCam de l'économie de batterie.
  Future<void> requestBatteryUnrestricted() => _call<void>('demanderSansRestrictionBatterie');

  /// Android : copie une vidéo dans la galerie (Films/sCam) ; renvoie son adresse.
  Future<String?> saveVideo(String path, String name) => _call<String>('rangerVideo', {'chemin': path, 'nom': name});

  /// Android : ouvre une vidéo de la galerie avec le lecteur du téléphone.
  Future<void> openVideo(String uri) => _call<void>('ouvrirVideo', uri);

  /// Garde l'écran allumé tant que l'application est au premier plan.
  Future<void> keepScreenOn(bool on) => _call<void>('ecranAllume', on);
}
