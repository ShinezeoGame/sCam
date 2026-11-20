import 'package:flutter/material.dart';

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
}
