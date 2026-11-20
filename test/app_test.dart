import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scam/data/net/protocol.dart';
import 'package:scam/models/camera.dart';
import 'package:scam/state/screen_controller.dart';
import 'package:scam/ui/pages/live_page.dart';
import 'package:scam/ui/pages/pair_page.dart';
import 'package:scam/ui/pages/settings_page.dart';
import 'package:scam/ui/widgets/controls.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(loadFonts);

  const sizes = {
    'fenêtre minimale 360×480': Size(360, 480),
    'fenêtre par défaut 420×760': Size(420, 760),
    'fenêtre agrandie 1100×700': Size(1100, 700),
  };

  /// Fait défiler la page jusqu'en bas : tout le contenu est construit et mesuré.
  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 14; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  /// Amène à l'écran un élément situé plus bas dans la page (la liste est construite à la demande).
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(finder, findsOneWidget);
  }

  Future<void> push(WidgetTester tester, Widget page) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  for (final MapEntry(key: label, value: size) in sizes.entries) {
    group(label, () {
      for (final dark in [false, true]) {
        final theme = dark ? 'sombre' : 'clair';

        testWidgets('premier lancement : choix du rôle ($theme)', (tester) async {
          final (app, _, _) = await pumpApp(tester, size, dark: dark);
          expect(find.text('Que fait cet appareil ?'), findsOneWidget);
          expect(find.text('Caméra'), findsOneWidget);
          await tester.tap(find.text('Écran'));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await tester.pump();
          expect(app.settings.role, DeviceRole.screen);
          expect(find.text('Aucune caméra pour l\'instant'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tearDownApp(tester, app);
        });

        testWidgets('caméra : accueil, code d\'appairage, réglages ($theme)', (tester) async {
          final (app, media, _) = await pumpApp(
            tester,
            size,
            role: DeviceRole.camera,
            dark: dark,
            name: longName,
            paired: {'s25': device('s25', 'Galaxy S25'), 'pc': device('pc', 'PC du bureau')},
          );
          final camera = app.camera!;
          expect(camera.running, isTrue, reason: 'la caméra démarre à l\'ouverture');
          await reveal(tester, find.text('Galaxy S25'));
          expect(tester.takeException(), isNull);

          camera.openPairing();
          await tester.pump();
          await reveal(tester, find.textContaining('Appairage ouvert'));
          camera.debugRaise(AlertKind.noise);
          await tester.pump();
          await scrollThrough(tester);

          // Réglages modifiés depuis la caméra elle-même.
          await camera.updateCameraSettings(camera.cameraSettings.copyWith(motionAlert: true));
          await tester.pump();
          expect(media.applied.last.$2.motionAlert, isTrue);

          await push(tester, const SettingsPage());
          await tester.tap(find.byWidgetPredicate((w) => w is AppSwitch && w.label == 'Flux MJPEG local'));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await tester.pump();
          expect(app.settings.mjpegEnabled, isTrue);
          expect(find.textContaining('/video.mjpg'), findsOneWidget);
          await scrollThrough(tester);
          await tearDownApp(tester, app);
        });

        testWidgets('écran : caméras, alertes, image en direct ($theme)', (tester) async {
          final (app, _, screenMedia) = await pumpApp(tester, size, role: DeviceRole.screen, dark: dark);
          final screen = app.screen!;
          fillScreen(screen);
          await tester.pump();
          expect(find.text('Chambre de Léo'), findsOneWidget);
          expect(find.textContaining('Mouvement'), findsWidgets);
          expect(tester.takeException(), isNull);
          await scrollThrough(tester);

          await push(tester, const LivePage(cameraId: 'leo'));
          expect(find.text('Écouter en arrière-plan'), findsOneWidget);
          expect(find.text('Éclaircir'), findsOneWidget);
          await tester.tap(find.text('Éclaircir'));
          await tester.pump();
          expect(screen.camera('leo')!.brighten, isTrue);
          await scrollThrough(tester);

          await push(tester, const PairPage());
          screen.debugSetDiscovered([
            DiscoveredCamera(
              const CameraAnnouncement(id: 'salon', name: 'Salon', port: scamPort, pairing: true),
              InternetAddress('192.168.1.30'),
            ),
          ]);
          await tester.pump();
          expect(find.text('Salon'), findsOneWidget);
          await scrollThrough(tester);
          expect(screenMedia.sessions, isEmpty, reason: 'la caméra simulée n\'est pas jointe');
          await tearDownApp(tester, app);
        });
      }
    });
  }
}
