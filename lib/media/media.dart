import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../models/camera.dart';

/// Envoie un message de signalisation WebRTC à l'appareil d'en face (par la liaison
/// chiffrée).
typedef SignalSink = void Function(Map<String, dynamic> message);

/// Mesures faites sur la caméra.
class Measures {
  const Measures({this.sound = 0, this.motion = 0});

  /// Niveau sonore, de 0 à 1.
  final double sound;

  /// Part de l'image qui a changé depuis la mesure précédente, de 0 à 1.
  final double motion;
}

/// Une transmission en cours vers un écran, ou depuis une caméra.
abstract class MediaSession {
  /// Traite un message de signalisation reçu de l'autre appareil.
  Future<void> onSignal(Map<String, dynamic> message);

  Future<void> close();
}

/// Ce que filme la caméra. Séparé du reste pour que les tests tournent sans caméra.
abstract class CameraMedia {
  /// Ouvre la caméra et le micro.
  Future<void> start(CameraSettings settings);

  Future<void> stop();

  bool get running;

  /// La caméra choisie a une lampe.
  bool get hasTorch;

  /// Applique des réglages modifiés pendant que la caméra filme.
  Future<void> apply(CameraSettings previous, CameraSettings next);

  /// Commence à transmettre vers un écran ; la caméra fait l'offre.
  Future<MediaSession> openSession(SignalSink signal);

  Future<Measures> measure();

  /// Dernière image, en JPEG, pour le flux MJPEG.
  Future<Uint8List?> snapshot();

  /// Aperçu local.
  Widget preview();

  /// La caméra sait enregistrer des extraits (Android).
  bool get canRecord;

  /// Objectifs avant et arrière (téléphone) ; faux pour une webcam.
  bool get canSwitchLens;

  /// Commence à enregistrer l'image et le son dans un fichier MP4 ; faux si impossible.
  Future<bool> startRecording(String path);

  Future<void> stopRecording();
}

/// Réception d'une caméra sur l'écran.
abstract class ViewerSession implements MediaSession {
  /// Vrai quand l'image arrive.
  ValueNotifier<bool> get connected;

  void setMuted(bool muted);

  /// Image reçue ; [brighten] éclaircit les scènes sombres (la nuit).
  Widget view({bool brighten = false, bool cover = false});
}

abstract class ScreenMedia {
  Future<ViewerSession> openSession(SignalSink signal);
}
