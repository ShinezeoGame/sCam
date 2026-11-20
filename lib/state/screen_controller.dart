import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/net/discovery.dart';
import '../data/net/pairing.dart';
import '../data/net/protocol.dart';
import '../data/settings.dart';
import '../data/system_bridge.dart';
import '../media/media.dart';
import '../models/camera.dart';
import 'app_controller.dart';

/// Une caméra appairée, vue de l'écran : liaison chiffrée permanente (pour l'état et les
/// alertes), et transmission de l'image quand on la regarde.
class CameraLink {
  CameraLink(this.device);

  PairedDevice device;
  MessageLink? link;
  CameraStatus? status;

  /// Transmission de l'image et du son, quand on regarde.
  ViewerSession? session;

  /// Vrai si la liaison est établie.
  bool get online => link != null && !link!.closed;
  String? error;
  bool muted = false;

  /// Éclaircir l'image (la nuit), sur cet écran seulement.
  bool brighten = false;

  /// Écouter en arrière-plan : la transmission continue hors de la page de la caméra.
  bool listening = false;

  int _attempts = 0;
  Timer? _retry;
  bool _connecting = false;
  CameraAlert? lastAlert;

  String get name => status?.name ?? device.name;
}

/// Caméra annoncée sur le réseau, pas encore appairée.
class DiscoveredCamera {
  const DiscoveredCamera(this.announcement, this.address);

  final CameraAnnouncement announcement;
  final InternetAddress address;
}

/// Rôle Écran : se relie aux caméras appairées, reçoit leurs alertes et les regarde.
class ScreenController extends ChangeNotifier {
  ScreenController({required this.app, required this.media});

  final AppController app;
  final ScreenMedia media;

  SystemBridge get bridge => app.bridge;
  Settings get settings => app.settings;

  Discovery? _discovery;
  StreamSubscription<SeenCamera>? _seenSub;
  final _links = <String, CameraLink>{};
  final _discovered = <String, (DiscoveredCamera, DateTime)>{};
  bool _disposed = false;

  /// Dernières alertes reçues, la plus récente d'abord.
  final alerts = <CameraAlert>[];

  /// Appairage en cours.
  PairingExchange? pairing;
  bool pairingBusy = false;

  List<CameraLink> get cameras => _links.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  CameraLink? camera(String id) => _links[id];

  /// Caméras du réseau dont l'appairage est ouvert.
  List<DiscoveredCamera> get pairable {
    final now = DateTime.now();
    return [
      for (final (camera, seen) in _discovered.values)
        if (camera.announcement.pairing &&
            now.difference(seen) < const Duration(seconds: 12) &&
            !_links.containsKey(camera.announcement.id))
          camera,
    ];
  }

  Future<void> start() async {
    for (final device in settings.paired.values) {
      _links[device.id] = CameraLink(device);
    }
    final discovery = Discovery(
      port: app.network.port,
      targets: app.network.discoveryTargets,
      interval: const Duration(seconds: 15),
    );
    _discovery = discovery;
    _seenSub = discovery.cameras.listen(_onSeen);
    try {
      await discovery.start();
    } on Object {
      // Sans découverte, les caméras sont jointes à leur dernière adresse connue.
    }
    for (final link in _links.values) {
      unawaited(_connect(link));
    }
    await _updateService();
  }

  void _onSeen(SeenCamera seen) {
    final a = seen.announcement;
    _discovered[a.id] = (DiscoveredCamera(a, seen.address), seen.seenAt);
    final link = _links[a.id];
    if (link != null) {
      final address = seen.address.address;
      if (link.device.address != address || link.device.port != a.port) {
        link.device = link.device.copyWith(address: address, port: a.port);
        _savePaired(link.device);
      }
      if (!link.online && !link._connecting) {
        link._retry?.cancel();
        unawaited(_connect(link));
      }
    }
    notifyListeners();
  }

  Future<void> _savePaired(PairedDevice device) =>
      app.update(settings.copyWith(paired: {...settings.paired, device.id: device}));

  Future<void> _connect(CameraLink camera) async {
    if (_disposed || camera.online || camera._connecting) return;
    final address = camera.device.address, port = camera.device.port;
    if (address == null || port == null) return;
    camera._connecting = true;
    try {
      final (link, it) = await Handshake.connect(
        address: InternetAddress(address),
        port: port,
        selfId: settings.deviceId,
        camera: camera.device,
      );
      if (_disposed || !_links.containsKey(camera.device.id)) {
        await link.close();
        return;
      }
      camera
        ..link = link
        ..error = null
        .._attempts = 0;
      notifyListeners();
      // Une transmission qui était en cours (écoute en arrière-plan) reprend.
      if (camera.session != null) {
        await camera.session!.close();
        camera.session = null;
        await watch(camera.device.id);
      }
      unawaited(_listen(camera, link, it));
    } on LinkException catch (e) {
      camera.error = e.message;
      _scheduleRetry(camera);
    } on Object {
      camera.error = null;
      _scheduleRetry(camera);
    } finally {
      camera._connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _scheduleRetry(CameraLink camera) {
    if (_disposed) return;
    camera._attempts++;
    final seconds = [3, 5, 10, 20, 30][camera._attempts.clamp(1, 5) - 1];
    camera._retry?.cancel();
    camera._retry = Timer(Duration(seconds: seconds), () => _connect(camera));
  }

  Future<void> _listen(CameraLink camera, MessageLink link, StreamIterator<Map<String, dynamic>> it) async {
    while (await it.moveNext()) {
      final message = it.current;
      switch (message['type']) {
        case 'etat':
          final status = CameraStatus.fromJson(message['etat']);
          if (status != null) {
            camera.status = status;
            if (status.name != camera.device.name) {
              camera.device = camera.device.copyWith(name: status.name);
              await _savePaired(camera.device);
            }
          }
        case 'alerte':
          final kind = AlertKind.values.where((k) => k.name == message['genre']).firstOrNull;
          if (kind != null) await _onAlert(camera, kind);
        case 'offre' || 'candidat':
          await camera.session?.onSignal(message);
        case 'erreur':
          final text = message['message'];
          if (text is String) app.showNotice('${camera.name} : $text', error: true);
          await camera.session?.close();
          camera.session = null;
        case 'fin':
          await camera.session?.close();
          camera.session = null;
      }
      if (!_disposed) notifyListeners();
    }
    // Liaison coupée : on réessaie.
    if (camera.link == link) camera.link = null;
    if (!_disposed) {
      notifyListeners();
      _scheduleRetry(camera);
    }
  }

  Future<void> _onAlert(CameraLink camera, AlertKind kind) async {
    final alert = CameraAlert(cameraId: camera.device.id, cameraName: camera.name, kind: kind, at: DateTime.now());
    camera.lastAlert = alert;
    alerts.insert(0, alert);
    if (alerts.length > 50) alerts.removeLast();
    await bridge.notifyAlert(
      title: kind == AlertKind.noise ? '${camera.name} : bruit' : '${camera.name} : mouvement',
      text: kind == AlertKind.noise ? 'Un bruit prolongé a été entendu.' : 'Un mouvement a été vu.',
    );
  }

  // ── Regarder ──

  /// Commence à recevoir l'image et le son d'une caméra.
  Future<ViewerSession?> watch(String cameraId) async {
    final camera = _links[cameraId];
    final link = camera?.link;
    if (camera == null || link == null || link.closed) return null;
    if (camera.session != null) return camera.session;
    final session = await media.openSession(link.send);
    session.setMuted(camera.muted);
    camera.session = session;
    await link.send({'type': 'regarder'});
    notifyListeners();
    await _updateService();
    return session;
  }

  /// Arrête la transmission, sauf si l'écoute en arrière-plan est demandée.
  Future<void> leave(String cameraId) async {
    final camera = _links[cameraId];
    if (camera == null || camera.listening) return;
    await stopWatching(cameraId);
  }

  Future<void> stopWatching(String cameraId) async {
    final camera = _links[cameraId];
    if (camera == null) return;
    camera.listening = false;
    final session = camera.session;
    camera.session = null;
    await camera.link?.send({'type': 'arreter'});
    await session?.close();
    if (!_disposed) notifyListeners();
    await _updateService();
  }

  void setListening(String cameraId, bool listening) {
    final camera = _links[cameraId];
    if (camera == null) return;
    camera.listening = listening;
    notifyListeners();
    _updateService();
  }

  void setMuted(String cameraId, bool muted) {
    final camera = _links[cameraId];
    if (camera == null) return;
    camera.muted = muted;
    camera.session?.setMuted(muted);
    notifyListeners();
  }

  void setBrighten(String cameraId, bool brighten) {
    final camera = _links[cameraId];
    if (camera == null) return;
    camera.brighten = brighten;
    notifyListeners();
  }

  /// Modifie les réglages d'une caméra (lampe, objectif, alertes…).
  Future<void> configure(String cameraId, CameraSettings next) async {
    final camera = _links[cameraId];
    if (camera?.link == null) return;
    final status = camera!.status;
    if (status != null) {
      // Affichage immédiat ; la caméra confirmera par son prochain état.
      camera.status = CameraStatus.fromJson({...status.toJson(), 'reglages': next.toJson()});
      notifyListeners();
    }
    await camera.link!.send({'type': 'reglages', 'reglages': next.toJson()});
  }

  // ── Appairage ──

  /// Lance l'appairage avec une caméra annoncée, ou jointe par son adresse.
  Future<void> pair(InternetAddress address, int port) async {
    if (pairingBusy || pairing != null) return;
    pairingBusy = true;
    notifyListeners();
    try {
      final exchange = await PairingExchange.requestFromScreen(
        address: address,
        port: port,
        selfId: settings.deviceId,
        selfName: settings.deviceName,
      );
      pairing = exchange;
      pairingBusy = false;
      notifyListeners();
      final device = await exchange.result;
      if (pairing == exchange) pairing = null;
      if (_disposed) return;
      if (device != null) {
        final saved = device.copyWith(address: address.address, port: port);
        await _savePaired(saved);
        final link = CameraLink(saved);
        _links[saved.id]?._retry?.cancel();
        await _links[saved.id]?.link?.close();
        _links[saved.id] = link;
        app.showNotice('« ${saved.name} » est appairée.');
        unawaited(_connect(link));
        await _updateService();
      } else if (exchange.failure != null) {
        app.showNotice(exchange.failure!, error: true);
      }
    } on LinkException catch (e) {
      app.showNotice(e.message, error: true);
    } on Object {
      app.showNotice('L\'appairage a échoué.', error: true);
    } finally {
      pairingBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Appairage par adresse (« 192.168.1.30 » ou « 192.168.1.30:47880 »).
  Future<void> pairByAddress(String text) async {
    final trimmed = text.trim();
    final parts = trimmed.split(':');
    final address = InternetAddress.tryParse(parts.first);
    final port = parts.length > 1 ? int.tryParse(parts[1]) : scamPort;
    if (address == null || port == null || parts.length > 2) {
      app.showNotice('Adresse invalide. Exemple : 192.168.1.30', error: true);
      return;
    }
    if (!isLocalAddress(address)) {
      app.showNotice('sCam ne fonctionne qu\'avec les adresses du réseau de la maison.', error: true);
      return;
    }
    await pair(address, port);
  }

  /// Oublie une caméra.
  Future<void> forget(String cameraId) async {
    final camera = _links.remove(cameraId);
    camera?._retry?.cancel();
    await camera?.session?.close();
    await camera?.link?.close();
    final paired = Map.of(settings.paired)..remove(cameraId);
    await app.update(settings.copyWith(paired: paired));
    notifyListeners();
    await _updateService();
  }

  Future<void> setBackground(bool enabled) async {
    await app.update(settings.copyWith(background: enabled));
    await _updateService();
    notifyListeners();
  }

  /// Sur Android, un service au premier plan garde les liaisons (alertes) et le son quand
  /// l'application passe en arrière-plan.
  Future<void> _updateService() async {
    if (_disposed) return;
    final listening = _links.values.where((c) => c.session != null).toList();
    if (!settings.background && listening.isEmpty || _links.isEmpty) {
      await bridge.stopService();
      return;
    }
    final n = _links.length;
    await bridge.startService(
      ServiceMode.screen,
      title: listening.isNotEmpty ? 'À l\'écoute : ${listening.map((c) => c.name).join(', ')}' : 'sCam veille',
      text: n == 1 ? 'Alertes de ${_links.values.first.name}' : 'Alertes de $n caméras',
    );
  }

  @visibleForTesting
  void debugSetDiscovered(List<DiscoveredCamera> cameras) {
    for (final c in cameras) {
      _discovered[c.announcement.id] = (c, DateTime.now());
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugSetCamera(PairedDevice device, {CameraStatus? status, bool online = false, CameraAlert? lastAlert}) {
    final link = _links[device.id] ?? CameraLink(device);
    link
      ..status = status
      ..lastAlert = lastAlert;
    _links[device.id] = link;
    if (online) _debugOnline.add(device.id);
    notifyListeners();
  }

  final _debugOnline = <String>{};

  /// Vrai si la caméra est jointe (ou déclarée jointe par un test).
  bool isOnline(CameraLink camera) => camera.online || _debugOnline.contains(camera.device.id);

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _seenSub?.cancel();
    for (final camera in _links.values) {
      camera._retry?.cancel();
      await camera.session?.close();
      await camera.link?.close();
    }
    await pairing?.cancel();
    await _discovery?.stop();
    await bridge.stopService();
    super.dispose();
  }
}
