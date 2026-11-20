import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scam/app.dart';
import 'package:scam/data/net/protocol.dart';
import 'package:scam/data/settings.dart';
import 'package:scam/models/camera.dart';
import 'package:scam/state/app_controller.dart';
import 'package:scam/state/screen_controller.dart';

import 'harness.dart';

/// Charge les vraies polices pour que les mesures de texte correspondent à l'application.
Future<void> loadFonts() async {
  final outfit = FontLoader('Outfit');
  for (final weight in ['300Light', '400Regular', '500Medium', '600SemiBold']) {
    final bytes = File('assets/fonts/Outfit_$weight.ttf').readAsBytesSync();
    outfit.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await outfit.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final material = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
  await material.load();
}

/// Clé de la zone capturée pour la documentation.
const captureKey = ValueKey('capture');

PairedDevice device(String id, String name) => PairedDevice(id: id, name: name, key: List.filled(32, 7));

const longName = 'Chambre de Léo et de Maëlle, au fond du couloir à gauche';

CameraStatus cameraStatus(
  String name, {
  bool running = true,
  int battery = 82,
  double sound = 0.32,
  CameraSettings settings = const CameraSettings(),
}) => CameraStatus(
  name: name,
  running: running,
  battery: battery,
  charging: true,
  temperature: 31,
  sound: sound,
  motion: 0.04,
  hasTorch: true,
  viewers: 1,
  settings: settings,
);

/// Affiche l'application dans une fenêtre de la taille donnée. Le réseau tourne pour de
/// bon (ports libres), la caméra et WebRTC sont simulés.
Future<(AppController, FakeCameraMedia, FakeScreenMedia)> pumpApp(
  WidgetTester tester,
  Size size, {
  DeviceRole? role,
  bool dark = false,
  String name = 'Galaxy S25',
  Map<String, PairedDevice> paired = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppController.debugCameraAllowed = true;
  final cameraMedia = FakeCameraMedia(), screenMedia = FakeScreenMedia();
  late AppController controller;
  await tester.runAsync(() async {
    final port = await freePort(), jpeg = await freePort();
    controller = AppController(
      store: MemoryStore(
        Settings(
          deviceId: 'moi',
          deviceName: name,
          role: role,
          theme: dark ? AppThemeMode.dark : AppThemeMode.light,
          paired: paired,
          mjpegPassword: 'a1b2c3d4e5f6',
        ),
      ),
      cameraMedia: () => cameraMedia,
      screenMedia: () => screenMedia,
      network: NetworkOptions(port: port, mjpegPort: jpeg, discoveryTargets: const []),
    );
    await controller.loadSettings();
    await controller.start();
  });
  controller.addresses = const ['192.168.1.42'];
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: SCamApp(controller: controller),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return (controller, cameraMedia, screenMedia);
}

/// Écran avec trois caméras dans des états différents.
void fillScreen(ScreenController screen) {
  screen.debugSetCamera(device('leo', 'Chambre de Léo'), status: cameraStatus('Chambre de Léo'), online: true);
  screen.debugSetCamera(
    device('entree', 'Entrée'),
    status: cameraStatus('Entrée', running: false, battery: 14),
    online: true,
    lastAlert: CameraAlert(
      cameraId: 'entree',
      cameraName: 'Entrée',
      kind: AlertKind.motion,
      at: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
  );
  screen.debugSetCamera(device('long', longName));
}

Future<void> tearDownApp(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(controller.dispose);
  await tester.pump(const Duration(seconds: 1));
}
