import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:scam/data/net/protocol.dart';
import 'package:scam/data/settings.dart';
import 'package:scam/media/media.dart';
import 'package:scam/models/camera.dart';
import 'package:scam/state/app_controller.dart';

/// Caméra simulée : pas de vrai capteur, des mesures imposées par le test.
class FakeCameraMedia implements CameraMedia {
  bool _running = false;
  Measures next = const Measures();
  final applied = <(CameraSettings, CameraSettings)>[];
  final sessions = <FakeCameraSession>[];
  Uint8List? jpeg = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);

  @override
  bool get running => _running;

  @override
  bool get hasTorch => true;

  @override
  Future<void> start(CameraSettings settings) async => _running = true;

  @override
  Future<void> stop() async => _running = false;

  @override
  Future<void> apply(CameraSettings previous, CameraSettings next) async => applied.add((previous, next));

  @override
  Future<MediaSession> openSession(SignalSink signal) async {
    final session = FakeCameraSession(signal);
    sessions.add(session);
    signal({'type': 'offre', 'sdp': 'offre-simulee'});
    return session;
  }

  @override
  Future<Measures> measure() async => next;

  @override
  Future<Uint8List?> snapshot() async => jpeg;

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF39424A));

  @override
  bool canRecord = true;

  @override
  bool get canSwitchLens => true;

  String? recordingTo;

  @override
  Future<bool> startRecording(String path) async {
    if (recordingTo != null) return false;
    recordingTo = path;
    // Un faux MP4 de 250 Ko : son téléchargement demande trois morceaux.
    File(path).writeAsBytesSync([for (var i = 0; i < 250 * 1024; i++) i % 251]);
    return true;
  }

  @override
  Future<void> stopRecording() async => recordingTo = null;
}

class FakeCameraSession implements MediaSession {
  FakeCameraSession(this.signal);

  final SignalSink signal;
  final received = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Future<void> onSignal(Map<String, dynamic> message) async => received.add(message);

  @override
  Future<void> close() async => closed = true;
}

class FakeScreenMedia implements ScreenMedia {
  final sessions = <FakeViewerSession>[];

  @override
  Future<ViewerSession> openSession(SignalSink signal) async {
    final session = FakeViewerSession(signal);
    sessions.add(session);
    return session;
  }
}

class FakeViewerSession implements ViewerSession {
  FakeViewerSession(this.signal);

  final SignalSink signal;
  final received = <Map<String, dynamic>>[];
  bool closed = false;
  bool muted = false;

  @override
  final connected = ValueNotifier(true);

  @override
  Future<void> onSignal(Map<String, dynamic> message) async {
    received.add(message);
    if (message['type'] == 'offre') signal({'type': 'reponse', 'sdp': 'reponse-simulee'});
  }

  @override
  void setMuted(bool value) => muted = value;

  @override
  Widget view({bool brighten = false, bool cover = false}) => const ColoredBox(color: Color(0xFF4A5560));

  @override
  Future<void> close() async => closed = true;
}

/// Port TCP libre sur cette machine.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Une caméra et un écran réels (réseau compris) sur cette machine.
class Pair {
  Pair(this.camera, this.screen, this.cameraMedia, this.screenMedia, this.temp);

  final AppController camera;
  final AppController screen;
  final FakeCameraMedia cameraMedia;
  final FakeScreenMedia screenMedia;

  /// Dossier temporaire : extraits de la caméra (`camera/`) et téléchargés (`ecran/`).
  final Directory temp;

  static Future<Pair> start({Map<String, PairedDevice> cameraPaired = const {}}) async {
    AppController.debugCameraAllowed = true;
    final cameraPort = await freePort(), screenPort = await freePort(), jpegPort = await freePort();
    final loopback = InternetAddress.loopbackIPv4;
    final cameraMedia = FakeCameraMedia(), screenMedia = FakeScreenMedia();
    final temp = await Directory.systemTemp.createTemp('scam-test');
    final camera = AppController(
      clipsDirectory: () async => Directory('${temp.path}/camera'),
      store: MemoryStore(
        Settings(role: DeviceRole.camera, deviceId: 'cam', deviceName: 'Chambre de Léo', paired: cameraPaired),
      ),
      cameraMedia: () => cameraMedia,
      network: NetworkOptions(port: cameraPort, mjpegPort: jpegPort, discoveryTargets: [(loopback, screenPort)]),
    );
    final screen = AppController(
      savedClipsDirectory: () async => Directory('${temp.path}/ecran'),
      store: MemoryStore(const Settings(role: DeviceRole.screen, deviceId: 'ecran', deviceName: 'Galaxy S25')),
      screenMedia: () => screenMedia,
      network: NetworkOptions(port: screenPort, discoveryTargets: [(loopback, cameraPort)]),
    );
    await camera.loadSettings();
    await screen.loadSettings();
    await camera.start();
    await screen.start();
    return Pair(camera, screen, cameraMedia, screenMedia, temp);
  }

  Future<void> stop() async {
    await screen.dispose();
    await camera.dispose();
    await temp.delete(recursive: true);
  }
}

/// Attend qu'une condition devienne vraie (au plus [timeout]).
Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('Condition jamais remplie');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
