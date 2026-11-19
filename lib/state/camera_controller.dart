import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/detection.dart';
import '../data/net/discovery.dart';
import '../data/net/mjpeg_server.dart';
import '../data/net/pairing.dart';
import '../data/net/protocol.dart';
import '../data/settings.dart';
import '../data/system_bridge.dart';
import '../media/media.dart';
import '../models/camera.dart';
import 'app_controller.dart';

/// Un écran appairé, connecté à la caméra.
class ScreenConnection {
  ScreenConnection(this.device, this.link);

  final PairedDevice device;
  final MessageLink link;
  MediaSession? session;

  /// Vrai quand l'écran regarde (image et son transmis).
  bool get watching => session != null;
}

/// Rôle Caméra : filme, écoute, mesure, alerte, et répond aux écrans appairés.
class CameraController extends ChangeNotifier {
  CameraController({required this.app, required this.media});

  final AppController app;
  final CameraMedia media;

  SystemBridge get bridge => app.bridge;
  Settings get settings => app.settings;
  CameraSettings get cameraSettings => settings.camera;

  ServerSocket? _server;
  Discovery? _discovery;
  MjpegServer? _mjpeg;
  Timer? _measureTimer;
  Timer? _statusTimer;
  Timer? _pairingTimer;
  final _detector = AlertDetector();
  final _connections = <ScreenConnection>[];
  bool _disposed = false;

  /// Port réellement utilisé (un autre que 47880 si celui-ci était pris).
  int port = 0;

  bool get running => media.running;
  bool starting = false;
  String? error;

  BatteryInfo battery = const BatteryInfo();
  Measures measures = const Measures();

  /// Dernières alertes levées, la plus récente d'abord.
  final alerts = <CameraAlert>[];

  /// Fin de l'ouverture de l'appairage ; `null` s'il est fermé.
  DateTime? pairingUntil;
  bool get pairingOpen => pairingUntil != null && DateTime.now().isBefore(pairingUntil!);

  /// Appairage en cours : le code à comparer avec celui de l'écran.
  PairingExchange? pendingPairing;

  List<ScreenConnection> get connections => List.unmodifiable(_connections);
  int get viewers => _connections.where((c) => c.watching).length;

  bool get mjpegRunning => _mjpeg?.boundPort != null;

  Future<void> start() async {
    await _bind();
    final discovery = Discovery(
      announce: () =>
          CameraAnnouncement(id: settings.deviceId, name: settings.deviceName, port: port, pairing: pairingOpen),
      port: app.network.port,
      targets: app.network.discoveryTargets,
    );
    _discovery = discovery;
    try {
      await discovery.start();
    } on Object {
      // Sans annonces, les écrans se reconnectent à la dernière adresse connue.
    }
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    await _refreshMjpeg();
    await startCamera();
  }

  Future<void> _bind() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, app.network.port);
    } on SocketException {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    port = _server!.port;
    _server!.listen(_onClient, onError: (Object _) {});
  }

  /// Ouvre la caméra et le micro, et garde l'appareil éveillé (service au premier plan).
  Future<void> startCamera() async {
    if (running || starting) return;
    starting = true;
    error = null;
    notifyListeners();
    try {
      if (!await bridge.requestPermissions(camera: true)) {
        error = 'sCam a besoin de la caméra et du micro. Autorisez-les dans les réglages d\'Android.';
        return;
      }
      await media.start(cameraSettings);
      await _updateService();
      _detector.reset();
      _measureTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _measure());
    } on Object catch (e) {
      error = 'Impossible d\'ouvrir la caméra ($e).';
      await media.stop();
    } finally {
      starting = false;
      if (!_disposed) notifyListeners();
      _broadcastStatus();
    }
  }

  Future<void> stopCamera() async {
    _measureTimer?.cancel();
    _measureTimer = null;
    for (final c in _connections) {
      await c.session?.close();
      c.session = null;
      await c.link.send({'type': 'fin'});
    }
    await media.stop();
    measures = const Measures();
    await bridge.stopService();
    if (!_disposed) notifyListeners();
    _broadcastStatus();
  }

  Future<void> _updateService() async {
    if (!running) return;
    final n = viewers;
    await bridge.startService(
      ServiceMode.camera,
      title: '${settings.deviceName} filme',
      text: n == 0 ? 'Personne ne regarde. Alertes actives.' : (n == 1 ? 'Un écran regarde.' : '$n écrans regardent.'),
    );
  }

  Future<void> _measure() async {
    if (!running) return;
    try {
      measures = await media.measure();
    } on Object {
      return;
    }
    for (final kind in _detector.sample(
      at: DateTime.now(),
      sound: measures.sound,
      motion: measures.motion,
      settings: cameraSettings,
    )) {
      _raise(kind);
    }
    if (!_disposed) notifyListeners();
  }

  void _raise(AlertKind kind) {
    final alert = CameraAlert(
      cameraId: settings.deviceId,
      cameraName: settings.deviceName,
      kind: kind,
      at: DateTime.now(),
    );
    alerts.insert(0, alert);
    if (alerts.length > 30) alerts.removeLast();
    for (final c in _connections) {
      c.link.send({'type': 'alerte', 'genre': kind.name, 'heure': alert.at.toIso8601String()});
    }
  }

  /// Lève une alerte à la main (tests et essai depuis l'interface).
  @visibleForTesting
  void debugRaise(AlertKind kind) => _raise(kind);

  Future<void> _tick() async {
    battery = await bridge.battery();
    if (pairingUntil != null && !pairingOpen) {
      closePairing();
    }
    _broadcastStatus();
    if (!_disposed) notifyListeners();
  }

  CameraStatus get status => CameraStatus(
    name: settings.deviceName,
    running: running,
    battery: battery.level,
    charging: battery.charging,
    temperature: battery.temperature,
    hot: battery.hot,
    sound: measures.sound,
    motion: measures.motion,
    viewers: viewers,
    hasTorch: media.hasTorch,
    settings: cameraSettings,
  );

  void _broadcastStatus() {
    if (_connections.isEmpty) return;
    final message = {'type': 'etat', 'etat': status.toJson()};
    for (final c in _connections) {
      c.link.send(message);
    }
  }

  void onRenamed() {
    _discovery?.send();
    _broadcastStatus();
    _updateService();
  }

  // ── Connexions des écrans ──

  Future<void> _onClient(Socket socket) async {
    if (!isLocalAddress(socket.remoteAddress)) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final link = MessageLink(socket);
    final it = StreamIterator(link.messages);
    final first = await MessageLink.next(it, Limits.handshakeTimeout);
    switch (first?['type']) {
      case 'appairage':
        await _onPairingRequest(link, it, first!);
      case 'bonjour':
        final device = await Handshake.accept(link: link, it: it, hello: first!, lookup: (id) => settings.paired[id]);
        if (device != null) await _serve(ScreenConnection(device, link), it);
      default:
        await link.close();
    }
  }

  Future<void> _onPairingRequest(
    MessageLink link,
    StreamIterator<Map<String, dynamic>> it,
    Map<String, dynamic> request,
  ) async {
    // L'appairage n'est possible que pendant les quelques minutes où il est ouvert sur la
    // caméra, et un seul à la fois.
    if (!pairingOpen || pendingPairing != null) {
      await link.send({'type': 'refus'});
      await link.close();
      return;
    }
    final PairingExchange? exchange;
    try {
      exchange = await PairingExchange.answerOnCamera(
        link: link,
        it: it,
        request: request,
        selfId: settings.deviceId,
        selfName: settings.deviceName,
      );
    } on Object {
      await link.close();
      return;
    }
    if (exchange == null) {
      await link.close();
      return;
    }
    pendingPairing = exchange;
    notifyListeners();
    final device = await exchange.result;
    if (pendingPairing == exchange) pendingPairing = null;
    if (_disposed) return;
    if (device != null) {
      await app.update(settings.copyWith(paired: {...settings.paired, device.id: device}));
      closePairing();
      app.showNotice('« ${device.name} » est appairé : il peut regarder cette caméra.');
    } else if (exchange.failure != null) {
      app.showNotice(exchange.failure!, error: true);
    }
    notifyListeners();
  }

  /// Ouvre l'appairage pendant trois minutes.
  void openPairing() {
    pairingUntil = DateTime.now().add(Limits.pairingWindow);
    _pairingTimer?.cancel();
    _pairingTimer = Timer(Limits.pairingWindow, closePairing);
    _discovery?.send();
    notifyListeners();
  }

  void closePairing() {
    _pairingTimer?.cancel();
    pairingUntil = null;
    pendingPairing?.cancel();
    _discovery?.send();
    if (!_disposed) notifyListeners();
  }

  /// Oublie un écran : il ne pourra plus se connecter sans nouvel appairage.
  Future<void> forget(String screenId) async {
    final paired = Map.of(settings.paired)..remove(screenId);
    await app.update(settings.copyWith(paired: paired));
    for (final c in _connections.where((c) => c.device.id == screenId).toList()) {
      await _drop(c);
    }
    notifyListeners();
  }

  Future<void> _serve(ScreenConnection connection, StreamIterator<Map<String, dynamic>> it) async {
    _connections.add(connection);
    notifyListeners();
    await connection.link.send({'type': 'etat', 'etat': status.toJson()});
    try {
      while (await it.moveNext()) {
        // Un écran oublié entre-temps est déconnecté.
        if (!settings.paired.containsKey(connection.device.id)) break;
        await _onMessage(connection, it.current);
      }
    } on Object {
      // Liaison perdue.
    }
    await _drop(connection);
  }

  Future<void> _drop(ScreenConnection connection) async {
    if (!_connections.remove(connection)) return;
    await connection.session?.close();
    connection.session = null;
    await connection.link.close();
    await _updateService();
    if (!_disposed) {
      notifyListeners();
      _broadcastStatus();
    }
  }

  Future<void> _onMessage(ScreenConnection c, Map<String, dynamic> message) async {
    switch (message['type']) {
      case 'regarder':
        if (!running) {
          await c.link.send({'type': 'erreur', 'message': 'La caméra est arrêtée.'});
          return;
        }
        await c.session?.close();
        c.session = await media.openSession(c.link.send);
        await _updateService();
        notifyListeners();
        _broadcastStatus();
      case 'reponse' || 'candidat':
        await c.session?.onSignal(message);
      case 'arreter':
        await c.session?.close();
        c.session = null;
        await _updateService();
        notifyListeners();
        _broadcastStatus();
      case 'reglages':
        await updateCameraSettings(CameraSettings.fromJson(message['reglages'], cameraSettings));
    }
  }

  /// Applique de nouveaux réglages (depuis la caméra ou depuis un écran).
  Future<void> updateCameraSettings(CameraSettings next) async {
    final previous = cameraSettings;
    if (next == previous) return;
    await app.update(settings.copyWith(camera: next));
    try {
      await media.apply(previous, next);
    } on Object {
      // La caméra garde ses réglages précédents pour ce qui n'a pas pu changer.
    }
    notifyListeners();
    _broadcastStatus();
  }

  // ── Flux MJPEG ──

  Future<void> setMjpeg(bool enabled) async {
    await app.update(settings.copyWith(mjpegEnabled: enabled));
    await _refreshMjpeg();
    notifyListeners();
  }

  Future<void> newMjpegPassword() async {
    await app.update(settings.copyWith(mjpegPassword: randomHex(6)));
    notifyListeners();
  }

  Future<void> _refreshMjpeg() async {
    if (settings.mjpegEnabled && _mjpeg == null) {
      final server = MjpegServer(
        snapshot: media.snapshot,
        password: () => settings.mjpegPassword,
        port: app.network.mjpegPort,
      );
      try {
        await server.start();
        _mjpeg = server;
      } on Object {
        app.showNotice('Le flux MJPEG n\'a pas pu démarrer : le port ${app.network.mjpegPort} est pris.', error: true);
      }
    } else if (!settings.mjpegEnabled && _mjpeg != null) {
      await _mjpeg!.stop();
      _mjpeg = null;
    }
  }

  int? get mjpegBoundPort => _mjpeg?.boundPort;

  @override
  Future<void> dispose() async {
    _disposed = true;
    _statusTimer?.cancel();
    _pairingTimer?.cancel();
    _measureTimer?.cancel();
    pendingPairing?.cancel();
    for (final c in _connections.toList()) {
      await c.session?.close();
      await c.link.close();
    }
    _connections.clear();
    await _mjpeg?.stop();
    await _server?.close();
    await _discovery?.stop();
    if (media.running) await media.stop();
    await bridge.stopService();
    super.dispose();
  }
}
