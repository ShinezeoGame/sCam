// Captures d'écran de la documentation (`docs/captures`). Elles ne sont produites que sur
// demande, pour ne pas réécrire des images à chaque exécution des tests :
//
//     SCAM_CAPTURES=1 flutter test test/captures_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scam/data/net/protocol.dart';
import 'package:scam/models/camera.dart';
import 'package:scam/ui/pages/live_page.dart';

import 'support/app_harness.dart';
import 'support/harness.dart';

const _window = Size(420, 760);

Future<void> capture(WidgetTester tester, String name) async {
  final element = tester.element(find.byKey(captureKey));
  await tester.runAsync(() => precacheImage(const AssetImage('assets/branding/logo.png'), element));
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/captures/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final enabled = Platform.environment.containsKey('SCAM_CAPTURES');
  setUpAll(loadFonts);

  testWidgets('écran : les caméras', skip: !enabled, (tester) async {
    final (app, _, _) = await pumpApp(tester, _window, role: DeviceRole.screen);
    final screen = app.screen!;
    screen.debugSetCamera(
      device('leo', 'Chambre de Léo'),
      status: cameraStatus('Chambre de Léo', sound: 0.41),
      online: true,
      lastAlert: CameraAlert(cameraId: 'leo', cameraName: 'Chambre de Léo', kind: AlertKind.noise, at: DateTime.now()),
    );
    screen.debugSetCamera(
      device('entree', 'Entrée'),
      status: cameraStatus('Entrée', battery: 64, sound: 0.12),
      online: true,
    );
    screen.alerts.addAll([
      CameraAlert(cameraId: 'leo', cameraName: 'Chambre de Léo', kind: AlertKind.noise, at: DateTime.now()),
      CameraAlert(
        cameraId: 'entree',
        cameraName: 'Entrée',
        kind: AlertKind.motion,
        at: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ]);
    await tester.pump();
    await capture(tester, 'ecran');
    await tearDownApp(tester, app);
  });

  testWidgets('écran sombre : image en direct', skip: !enabled, (tester) async {
    final (app, _, _) = await pumpApp(tester, _window, role: DeviceRole.screen, dark: true);
    app.screen!.debugSetCamera(
      device('leo', 'Chambre de Léo'),
      status: cameraStatus('Chambre de Léo', settings: const CameraSettings(motionAlert: true)),
      online: true,
      session: FakeViewerSession((_) {}),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(MaterialPageRoute<void>(builder: (_) => const LivePage(cameraId: 'leo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'direct');
    await tearDownApp(tester, app);
  });

  testWidgets('caméra : code d\'appairage', skip: !enabled, (tester) async {
    final (app, _, _) = await pumpApp(
      tester,
      _window,
      role: DeviceRole.camera,
      name: 'Chambre de Léo',
      paired: {'s25': device('s25', 'Galaxy S25')},
    );
    app.camera!.openPairing();
    await tester.pump();
    await capture(tester, 'camera');
    await tearDownApp(tester, app);
  });
}
