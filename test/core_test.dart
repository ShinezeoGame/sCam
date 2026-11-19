import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scam/core/crypto.dart';
import 'package:scam/core/detection.dart';
import 'package:scam/data/net/mjpeg_server.dart';
import 'package:scam/data/net/pairing.dart';
import 'package:scam/data/net/protocol.dart';
import 'package:scam/data/settings.dart';
import 'package:scam/models/camera.dart';

import 'support/harness.dart';

/// Appaire l'écran et la caméra d'une paire, codes confirmés des deux côtés.
Future<void> pairDevices(Pair pair) async {
  final camera = pair.camera.camera!, screen = pair.screen.screen!;
  camera.openPairing();
  await until(() => screen.pairable.isNotEmpty);
  final found = screen.pairable.single;
  expect(found.announcement.name, 'Chambre de Léo');
  final pairing = screen.pair(found.address, found.announcement.port);
  await until(() => camera.pendingPairing != null && screen.pairing != null);
  // Les deux écrans affichent le même code.
  expect(camera.pendingPairing!.code, screen.pairing!.code);
  expect(camera.pendingPairing!.code, matches(RegExp(r'^\d{6}$')));
  await screen.pairing!.answer(true);
  await camera.pendingPairing!.answer(true);
  await pairing;
  await until(() => pair.camera.settings.paired.containsKey('ecran') && pair.screen.settings.paired.containsKey('cam'));
  await until(() => screen.camera('cam')?.online == true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('chiffrement', () {
    test('les deux côtés tirent la même clé et le même code', () async {
      final a = await ScamCrypto.newKeyPair(), b = await ScamCrypto.newKeyPair();
      final pa = await ScamCrypto.publicKeyOf(a), pb = await ScamCrypto.publicKeyOf(b);
      final na = ScamCrypto.random(16), nb = ScamCrypto.random(16);
      final left = await ScamCrypto.pairingSecret(
        own: a,
        remotePublicKey: pb,
        screenPublicKey: pa,
        cameraPublicKey: pb,
        screenNonce: na,
        cameraNonce: nb,
      );
      final right = await ScamCrypto.pairingSecret(
        own: b,
        remotePublicKey: pa,
        screenPublicKey: pa,
        cameraPublicKey: pb,
        screenNonce: na,
        cameraNonce: nb,
      );
      expect(left.key, right.key);
      expect(left.code, right.code);
      expect(left.key, hasLength(32));
    });

    test('un message altéré ou rejoué est refusé', () async {
      final key = await ScamCrypto.sessionKey(ScamCrypto.random(32), ScamCrypto.random(16), ScamCrypto.random(16));
      final screen = SessionCipher(key, isScreen: true), camera = SessionCipher(key, isScreen: false);
      final sealed = await screen.seal(utf8.encode('bonjour'));
      expect(utf8.decode(await camera.open(sealed)), 'bonjour');
      // Rejoué : le compteur a avancé, le déchiffrement échoue.
      await expectLater(camera.open(sealed), throwsA(anything));
      final other = await screen.seal(utf8.encode('suite'));
      final tampered = [...other]..[0] ^= 1;
      await expectLater(SessionCipher(key, isScreen: false).open(tampered), throwsA(anything));
      // Un message ne peut pas être renvoyé à son expéditeur (sens différents).
      final back = await screen.seal(utf8.encode('écho'));
      await expectLater(SessionCipher(key, isScreen: true).open(back), throwsA(anything));
    });
  });

  group('réseau local seulement', () {
    test('adresses', () {
      for (final local in ['192.168.1.20', '10.0.0.5', '172.20.1.1', '127.0.0.1', '169.254.3.4', 'fd00::1']) {
        expect(isLocalAddress(InternetAddress(local)), isTrue, reason: local);
      }
      for (final remote in ['8.8.8.8', '172.32.0.1', '2a01:cb00::1']) {
        expect(isLocalAddress(InternetAddress(remote)), isFalse, reason: remote);
      }
    });

    test('candidats WebRTC', () {
      expect(isLocalCandidate('candidate:1 1 udp 2122260223 192.168.1.20 54321 typ host generation 0'), isTrue);
      expect(isLocalCandidate('candidate:1 1 udp 2122260223 4b1e-aa.local 54321 typ host'), isTrue);
      expect(isLocalCandidate('candidate:2 1 udp 1686052607 90.12.3.4 54321 typ srflx raddr 0.0.0.0 rport 0'), isFalse);
      expect(isLocalCandidate('candidate:3 1 udp 2122260223 90.12.3.4 54321 typ host'), isFalse);
      expect(isLocalCandidate('n\'importe quoi'), isFalse);
    });
  });

  group('détection', () {
    final start = DateTime(2026, 11, 19, 22);
    DateTime at(int ms) => start.add(Duration(milliseconds: ms));

    test('un bruit bref n\'alerte pas, des pleurs oui', () {
      final detector = AlertDetector();
      const settings = CameraSettings(noiseThreshold: 0.5);
      // Une porte qui claque : une seule mesure forte.
      var alerts = <AlertKind>[];
      for (var i = 0; i < 6; i++) {
        alerts += detector.sample(at: at(i * 500), sound: i == 2 ? 0.9 : 0.1, motion: 0, settings: settings);
      }
      expect(alerts, isEmpty);
      // Des pleurs : fort pendant plusieurs mesures de suite.
      for (var i = 6; i < 12; i++) {
        alerts += detector.sample(at: at(i * 500), sound: 0.8, motion: 0, settings: settings);
      }
      expect(alerts, [AlertKind.noise]);
      // Puis silence pendant le délai entre deux alertes, même si ça continue.
      for (var i = 12; i < 40; i++) {
        alerts += detector.sample(at: at(i * 500), sound: 0.8, motion: 0, settings: settings);
      }
      expect(alerts, [AlertKind.noise]);
    });

    test('mouvement : deux mesures de suite au-delà du seuil', () {
      final detector = AlertDetector();
      const settings = CameraSettings(noiseAlert: false, motionAlert: true, motionSensitivity: 0.5);
      expect(AlertDetector.motionThreshold(0.5), closeTo(0.13, 0.001));
      expect(detector.sample(at: at(0), sound: 1, motion: 0.3, settings: settings), isEmpty);
      expect(detector.sample(at: at(500), sound: 1, motion: 0.02, settings: settings), isEmpty);
      expect(detector.sample(at: at(1000), sound: 1, motion: 0.3, settings: settings), isEmpty);
      expect(detector.sample(at: at(1500), sound: 1, motion: 0.3, settings: settings), [AlertKind.motion]);
    });

    test('alertes coupées : rien', () {
      final detector = AlertDetector();
      const settings = CameraSettings(noiseAlert: false, motionAlert: false);
      for (var i = 0; i < 20; i++) {
        expect(detector.sample(at: at(i * 500), sound: 1, motion: 1, settings: settings), isEmpty);
      }
    });
  });

  group('caméra et écran réels', () {
    late Pair pair;
    setUp(() async => pair = await Pair.start());
    tearDown(() async => pair.stop());

    test('appairage, état, alerte, image et réglages', () async {
      await pairDevices(pair);
      final camera = pair.camera.camera!, screen = pair.screen.screen!;
      expect(camera.pairingOpen, isFalse, reason: 'l\'appairage se ferme une fois conclu');

      // L'état de la caméra arrive à l'écran.
      await until(() => screen.camera('cam')?.status?.running == true);
      expect(screen.camera('cam')!.name, 'Chambre de Léo');

      // Une alerte levée sur la caméra arrive à l'écran.
      camera.debugRaise(AlertKind.noise);
      await until(() => screen.alerts.isNotEmpty);
      expect(screen.alerts.first.kind, AlertKind.noise);
      expect(screen.alerts.first.cameraName, 'Chambre de Léo');

      // Regarder : l'offre de la caméra et la réponse de l'écran passent par la liaison chiffrée.
      await screen.watch('cam');
      await until(() => pair.cameraMedia.sessions.isNotEmpty && pair.screenMedia.sessions.isNotEmpty);
      await until(() => pair.cameraMedia.sessions.single.received.isNotEmpty);
      expect(pair.screenMedia.sessions.single.received.single['sdp'], 'offre-simulee');
      expect(pair.cameraMedia.sessions.single.received.single['sdp'], 'reponse-simulee');
      await until(() => camera.viewers == 1);

      // Lampe allumée depuis l'écran : la caméra applique le réglage.
      final current = screen.camera('cam')!.status!.settings;
      await screen.configure('cam', current.copyWith(torch: true, noiseThreshold: 0.7));
      await until(() => pair.camera.settings.camera.torch);
      expect(pair.camera.settings.camera.noiseThreshold, 0.7);
      expect(pair.cameraMedia.applied.last.$2.torch, isTrue);

      await screen.stopWatching('cam');
      await until(() => camera.viewers == 0);
      expect(pair.cameraMedia.sessions.single.closed, isTrue);
    });

    test('un code refusé n\'appaire rien', () async {
      final camera = pair.camera.camera!, screen = pair.screen.screen!;
      camera.openPairing();
      await until(() => screen.pairable.isNotEmpty);
      final found = screen.pairable.single;
      final pairing = screen.pair(found.address, found.announcement.port);
      await until(() => camera.pendingPairing != null && screen.pairing != null);
      await screen.pairing!.answer(true);
      await camera.pendingPairing!.answer(false);
      await pairing;
      expect(pair.camera.settings.paired, isEmpty);
      expect(pair.screen.settings.paired, isEmpty);
      expect(pair.screen.notice?.error, isTrue);
    });

    test('sans appairage ouvert sur la caméra, la demande est refusée', () async {
      final camera = pair.camera.camera!, screen = pair.screen.screen!;
      await screen.pair(InternetAddress.loopbackIPv4, camera.port);
      expect(pair.screen.notice?.message, contains('pas ouvert'));
      expect(camera.pendingPairing, isNull);
    });

    test('un appareil inconnu ou oublié est refusé', () async {
      final camera = pair.camera.camera!;
      // Un écran qui n'a jamais été appairé, avec une clé inventée.
      final stranger = PairedDevice(id: 'intrus', name: 'Intrus', key: ScamCrypto.random(32));
      await expectLater(
        Handshake.connect(address: InternetAddress.loopbackIPv4, port: camera.port, selfId: 'intrus', camera: stranger),
        throwsA(isA<LinkException>()),
      );
      // Un identifiant connu mais une mauvaise clé.
      await pairDevices(pair);
      final impostor = PairedDevice(id: 'cam', name: 'x', key: ScamCrypto.random(32));
      await expectLater(
        Handshake.connect(address: InternetAddress.loopbackIPv4, port: camera.port, selfId: 'ecran', camera: impostor),
        throwsA(isA<LinkException>()),
      );
      expect(camera.connections, hasLength(1));
      // Oublié par la caméra : l'écran est déconnecté et ne peut plus revenir.
      await camera.forget('ecran');
      await until(() => pair.screen.screen!.camera('cam')?.online == false);
      await until(() => pair.screen.screen!.camera('cam')?.error != null, timeout: const Duration(seconds: 15));
      expect(pair.screen.screen!.camera('cam')!.error, contains('appairez'));
    });
  });

  group('flux MJPEG', () {
    test('mot de passe exigé, image et flux servis', () async {
      // Le banc d'essai de Flutter remplace les clients HTTP par un faux : on veut le vrai.
      HttpOverrides.global = null;
      final port = await freePort();
      final server = MjpegServer(
        snapshot: () async => FakeCameraMedia().jpeg,
        password: () => 'secret',
        port: port,
        frameInterval: const Duration(milliseconds: 50),
      );
      await server.start();
      final client = HttpClient();
      try {
        Future<HttpClientResponse> get(String path, {String? auth}) async {
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
          if (auth != null) request.headers.set('authorization', 'Basic ${base64Encode(utf8.encode(auth))}');
          return request.close();
        }

        expect((await get('/image.jpg')).statusCode, 401);
        expect((await get('/image.jpg', auth: 'scam:faux')).statusCode, 401);
        final ok = await get('/image.jpg', auth: 'scam:secret');
        expect(ok.statusCode, 200);
        expect(await ok.fold<List<int>>([], (a, b) => a..addAll(b)), FakeCameraMedia().jpeg);
        expect((await get('/image.jpg?mdp=secret')).statusCode, 200);

        final stream = await get('/video.mjpg', auth: 'scam:secret');
        expect(stream.headers.contentType?.mimeType, 'multipart/x-mixed-replace');
        final first = await stream.first;
        expect(ascii.decode(first.take(20).toList(), allowInvalid: true), startsWith('--scamimage'));
      } finally {
        client.close(force: true);
        await server.stop();
      }
    });
  });
}
