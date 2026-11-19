import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// Une caméra entendue sur le réseau local.
class SeenCamera {
  const SeenCamera(this.announcement, this.address, this.seenAt);

  final CameraAnnouncement announcement;
  final InternetAddress address;
  final DateTime seenAt;
}

/// Découverte des caméras du réseau local (reprise de sDrop).
///
/// Une caméra annonce régulièrement qui elle est par un petit message UDP, envoyé à la fois
/// en multidiffusion et en diffusion (selon les box et les téléphones, l'un des deux
/// seulement passe). Un écran qui démarre envoie une « sonde » à laquelle les caméras
/// répondent tout de suite, sans attendre leur prochaine annonce.
class Discovery {
  Discovery({this.announce, this.port = scamPort, this.targets, this.interval = const Duration(seconds: 4)});

  /// Ce que la caméra annonce (relu à chaque envoi). `null` : cet appareil est un écran.
  final CameraAnnouncement Function()? announce;

  final int port;

  /// Destinataires imposés (tests). `null` : multidiffusion et diffusion du réseau local.
  final List<(InternetAddress, int)>? targets;
  final Duration interval;

  final _seen = StreamController<SeenCamera>.broadcast();

  /// Caméras entendues (les annonces de cet appareil sont ignorées).
  Stream<SeenCamera> get cameras => _seen.stream;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<(InternetAddress, int)> _resolved = const [];
  DateTime _resolvedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Faux si le port d'écoute était déjà pris : l'appareil envoie mais n'entend rien.
  bool listening = false;

  Future<void> start() async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      listening = true;
    } on SocketException {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _socket = socket;
    socket.broadcastEnabled = true;
    if (targets == null && listening) await _joinMulticast(socket);
    socket.listen(_onEvent, onError: (Object _) {});
    unawaited(send());
    _timer = Timer.periodic(interval, (_) => send());
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    final group = InternetAddress(scamMulticastGroup);
    try {
      socket.joinMulticast(group);
    } on Object {
      // Certains systèmes exigent de nommer l'interface : on essaie ci-dessous.
    }
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        try {
          socket.joinMulticast(group, interface);
        } on Object {
          // Interface sans multidiffusion : la diffusion prendra le relais.
        }
      }
    } on Object {
      // Liste des interfaces indisponible.
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    for (var datagram = socket.receive(); datagram != null; datagram = socket.receive()) {
      if (datagram.data.length > 1024 || !isLocalAddress(datagram.address)) continue;
      Object? json;
      try {
        json = jsonDecode(utf8.decode(datagram.data));
      } on Object {
        continue;
      }
      if (json is Map && json['scam'] == protocolVersion && json['sonde'] == true) {
        // Un écran cherche les caméras : on lui répond directement.
        if (announce != null) _sendTo(datagram.address, datagram.port);
        continue;
      }
      final camera = CameraAnnouncement.fromJson(json);
      final self = announce;
      if (camera == null || (self != null && camera.id == self().id)) continue;
      if (!_seen.isClosed) _seen.add(SeenCamera(camera, datagram.address, DateTime.now()));
    }
  }

  List<int> _message() {
    final self = announce;
    return utf8.encode(jsonEncode(self == null ? {'scam': protocolVersion, 'sonde': true} : self().toJson()));
  }

  void _sendTo(InternetAddress address, int targetPort) {
    try {
      _socket?.send(_message(), address, targetPort);
    } on Object {
      // Réseau momentanément indisponible.
    }
  }

  /// Envoie une annonce (caméra) ou une sonde (écran) tout de suite.
  Future<void> send() async {
    if (_socket == null) return;
    // Un écran ne sonde qu'au démarrage et de loin en loin : les caméras s'annoncent seules.
    for (final (address, targetPort) in await _destinations()) {
      _sendTo(address, targetPort);
    }
  }

  Future<List<(InternetAddress, int)>> _destinations() async {
    final fixed = targets;
    if (fixed != null) return fixed;
    if (DateTime.now().difference(_resolvedAt) < const Duration(seconds: 20)) return _resolved;
    final addresses = <String>{scamMulticastGroup, '255.255.255.255'};
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final address in interface.addresses) {
          // Diffusion dirigée, en supposant le masque courant des réseaux domestiques (/24).
          final parts = address.address.split('.');
          if (parts.length == 4) addresses.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } on Object {
      // On garde la multidiffusion et la diffusion générale.
    }
    _resolved = [for (final address in addresses) (InternetAddress(address), port)];
    _resolvedAt = DateTime.now();
    return _resolved;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
    await _seen.close();
  }
}

/// Adresses de cet appareil sur le réseau local, pour les afficher à l'utilisateur.
Future<List<String>> localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address.address,
    ];
  } on Object {
    return const [];
  }
}
