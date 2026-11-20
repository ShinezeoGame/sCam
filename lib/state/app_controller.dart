import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/net/discovery.dart';
import '../data/net/protocol.dart';
import '../data/settings.dart';
import '../data/system_bridge.dart';
import '../media/media.dart';
import 'camera_controller.dart';
import 'screen_controller.dart';

/// Message affiché en haut de la page (résultat d'une action).
class Notice {
  const Notice(this.message, {this.error = false});

  final String message;
  final bool error;
}

/// Réglages réseau imposés (tests) : ports libres et destinataires des annonces.
class NetworkOptions {
  const NetworkOptions({this.port = scamPort, this.mjpegPort = defaultMjpegPort, this.discoveryTargets});

  final int port;
  final int mjpegPort;
  final List<(InternetAddress, int)>? discoveryTargets;
}

/// État de l'application : réglages, rôle choisi, et le contrôleur de ce rôle.
class AppController extends ChangeNotifier {
  AppController({
    SettingsStore? store,
    this.bridge = const SystemBridge(),
    this.cameraMedia,
    this.screenMedia,
    this.network = const NetworkOptions(),
    Future<Directory> Function()? clipsDirectory,
    Future<Directory> Function()? savedClipsDirectory,
  }) : _store = store ?? DiskStore(),
       clipsDirectory = clipsDirectory ?? _defaultClips,
       savedClipsDirectory = savedClipsDirectory ?? _defaultSavedClips;

  /// Dossier des extraits enregistrés par la caméra (espace privé de l'application).
  final Future<Directory> Function() clipsDirectory;

  /// Dossier où un écran (hors Android) range les extraits téléchargés : Vidéos\sCam.
  /// Sur Android, ils vont dans la galerie (Films/sCam) par le code natif.
  final Future<Directory> Function() savedClipsDirectory;

  static Future<Directory> _defaultClips() async =>
      Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}extraits');

  static Future<Directory> _defaultSavedClips() async {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null) return Directory('$home${Platform.pathSeparator}Videos${Platform.pathSeparator}sCam');
    return Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}sCam');
  }

  final SettingsStore _store;
  final SystemBridge bridge;
  final CameraMedia Function()? cameraMedia;
  final ScreenMedia Function()? screenMedia;
  final NetworkOptions network;

  Settings _settings = const Settings();
  Settings get settings => _settings;

  Notice? _notice;
  Notice? get notice => _notice;
  Timer? _noticeTimer;

  CameraController? camera;
  ScreenController? screen;

  List<String> addresses = const [];
  bool _started = false;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Le rôle Caméra existe sur Android (téléphone) et sous Windows (webcam du PC).
  bool get canBeCamera => isAndroid || isWindows || debugCameraAllowed;

  @visibleForTesting
  static bool debugCameraAllowed = false;

  Future<void> loadSettings() async {
    var s = await _store.load();
    if (s.deviceId.isEmpty) s = s.copyWith(deviceId: randomHex());
    if (s.deviceName.isEmpty) s = s.copyWith(deviceName: await bridge.deviceName());
    if (s.mjpegPassword.isEmpty) s = s.copyWith(mjpegPassword: randomHex(6));
    _settings = s;
    await _store.save(s);
  }

  /// Démarre le rôle choisi (rien tant qu'aucun rôle n'est choisi).
  Future<void> start() async {
    _started = true;
    addresses = await localAddresses();
    await bridge.setMulticastLock(true);
    await _startRole();
    notifyListeners();
  }

  Future<void> _startRole() async {
    switch (_settings.role) {
      case null:
        return;
      case DeviceRole.camera:
        final controller = CameraController(app: this, media: (cameraMedia ?? _defaultCameraMedia)());
        camera = controller;
        controller.addListener(notifyListeners);
        await controller.start();
      case DeviceRole.screen:
        final controller = ScreenController(app: this, media: (screenMedia ?? _defaultScreenMedia)());
        screen = controller;
        controller.addListener(notifyListeners);
        await controller.start();
    }
  }

  // Remplacés au démarrage par `main.dart` (WebRTC) ; jamais appelés dans les tests.
  static CameraMedia Function() _defaultCameraMedia = () => throw UnsupportedError('Caméra indisponible');
  static ScreenMedia Function() _defaultScreenMedia = () => throw UnsupportedError('Réception indisponible');

  static void useMedia({required CameraMedia Function() camera, required ScreenMedia Function() screen}) {
    _defaultCameraMedia = camera;
    _defaultScreenMedia = screen;
  }

  Future<void> _stopRole() async {
    final c = camera, s = screen;
    camera = null;
    screen = null;
    c?.removeListener(notifyListeners);
    s?.removeListener(notifyListeners);
    await c?.dispose();
    await s?.dispose();
  }

  /// Change le rôle de l'appareil. Les appairages sont oubliés : ils ne valent que pour
  /// un rôle (une caméra connaît des écrans, un écran des caméras).
  Future<void> chooseRole(DeviceRole role) async {
    if (role == _settings.role) return;
    await _stopRole();
    final previous = _settings.role;
    await update(_settings.copyWith(role: role, paired: previous == null ? _settings.paired : const {}));
    if (_started) await _startRole();
    notifyListeners();
  }

  Future<void> update(Settings next) async {
    _settings = next;
    notifyListeners();
    await _store.save(next);
  }

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _settings.deviceName) return;
    await update(_settings.copyWith(deviceName: trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed));
    camera?.onRenamed();
  }

  void setTheme(AppThemeMode mode) => update(_settings.copyWith(theme: mode));

  void showNotice(String message, {bool error = false}) {
    _notice = Notice(message, error: error);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 8), clearNotice);
    notifyListeners();
  }

  void clearNotice() {
    _noticeTimer?.cancel();
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _noticeTimer?.cancel();
    await _stopRole();
    super.dispose();
  }
}
