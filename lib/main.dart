import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'app.dart';
import 'data/system_bridge.dart';
import 'media/webrtc_media.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppController.useMedia(camera: () => WebRtcCameraMedia(const SystemBridge()), screen: WebRtcScreenMedia.new);
  final controller = AppController();
  // Les réglages sont lus avant le premier affichage : le thème choisi s'applique d'emblée.
  await controller.loadSettings();
  runApp(SCamApp(controller: controller));
  // Le rôle choisi démarre une fois l'interface affichée.
  await controller.start();
  await _selfTest(controller);
}

/// Essai de démarrage de la CI : si `SCAM_ESSAI` désigne un fichier, l'application y écrit
/// un compte rendu une fois lancée (WebRTC chargé, réseau prêt). Sans cette variable, rien.
Future<void> _selfTest(AppController controller) async {
  final path = Platform.environment['SCAM_ESSAI'];
  if (path == null || path.isEmpty) return;
  final report = <String, Object?>{'scam': 1, 'nom': controller.settings.deviceName};
  try {
    final pc = await createPeerConnection({'iceServers': <Object>[], 'sdpSemantics': 'unified-plan'});
    // Comme un écran qui reçoit : une piste vidéo et une piste audio en réception seule.
    for (final kind in [RTCRtpMediaType.RTCRtpMediaTypeVideo, RTCRtpMediaType.RTCRtpMediaTypeAudio]) {
      await pc.addTransceiver(
        kind: kind,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
    final offer = await pc.createOffer();
    final sdp = offer.sdp ?? '';
    report['webrtc'] = sdp.contains('m=video') && sdp.contains('m=audio');
    report['sdp'] = sdp.length;
    await pc.close();
  } on Object catch (e) {
    report['webrtc'] = false;
    report['erreur'] = '$e';
  }
  report['adresses'] = controller.addresses;
  await File(path).writeAsString(jsonEncode(report));
}
