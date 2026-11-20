import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/crypto.dart';

/// Port des annonces (UDP) et des connexions chiffrées (TCP) de la caméra.
const scamPort = 47880;

/// Port du flux MJPEG facultatif (sDash, Home Assistant).
const defaultMjpegPort = 47881;

/// Groupe de multidiffusion des annonces, limité au réseau local.
const scamMulticastGroup = '239.83.67.77';

/// Version du protocole.
const protocolVersion = 1;

abstract final class Limits {
  /// Taille maximale d'un message (une description de session WebRTC fait quelques Ko).
  static const frameBytes = 256 * 1024;

  /// Durée laissée pour terminer un appairage, codes comparés compris.
  static const pairingTimeout = Duration(minutes: 2);

  /// Durée d'ouverture de l'appairage sur la caméra.
  static const pairingWindow = Duration(minutes: 3);

  /// Durée laissée à un écran pour prouver qu'il est appairé.
  static const handshakeTimeout = Duration(seconds: 10);
}

/// Rôle d'un appareil.
enum DeviceRole {
  /// Filme et écoute.
  camera,

  /// Regarde une ou plusieurs caméras.
  screen,
}

/// Annonce d'une caméra sur le réseau local. Elle ne contient rien de secret.
class CameraAnnouncement {
  const CameraAnnouncement({required this.id, required this.name, required this.port, this.pairing = false});

  final String id;
  final String name;
  final int port;

  /// Vrai quand l'appairage est ouvert sur la caméra.
  final bool pairing;

  Map<String, dynamic> toJson() => {'scam': protocolVersion, 'id': id, 'nom': name, 'port': port, 'appairage': pairing};

  static CameraAnnouncement? fromJson(Object? json) {
    if (json is! Map || json['scam'] != protocolVersion) return null;
    final id = json['id'], name = json['nom'], port = json['port'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (name is! String || name.length > 80) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    return CameraAnnouncement(id: id, name: name, port: port, pairing: json['appairage'] == true);
  }
}

/// Vrai pour une adresse du réseau local (privée, lien local ou cet appareil) : sCam
/// refuse toute connexion venue d'ailleurs.
bool isLocalAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) return true;
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final a = raw[0], b = raw[1];
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }
  if (address.type == InternetAddressType.IPv6) {
    // Adresses locales uniques (fc00::/7).
    return (raw[0] & 0xfe) == 0xfc;
  }
  return false;
}

/// Liaison TCP qui échange des messages JSON, chacun précédé de sa longueur (4 octets).
///
/// Le chiffrement commence à un point précis de l'échange, dans chaque sens : à l'envoi,
/// pour les messages envoyés après [encryptSending] ; à la réception, pour les messages
/// qui suivent le message en clair désigné par [encryptReceivingAfter].
class MessageLink {
  MessageLink(this.socket) {
    _subscription = socket.listen(
      _onData,
      onError: (Object _) => close(),
      // Les derniers messages reçus sont livrés avant la fermeture.
      onDone: () => _decoding.then((_) => close()),
      cancelOnError: true,
    );
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder(copy: false);
  final _incoming = StreamController<Map<String, dynamic>>();
  SessionCipher? _sendCipher;
  SessionCipher? _receiveCipher;
  (String, SessionCipher)? _armed;
  Future<void> _decoding = Future.value();
  Future<void> _sending = Future.value();
  bool _closed = false;

  /// Messages reçus, dans l'ordre. Le flux se ferme avec la liaison.
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  bool get closed => _closed;

  InternetAddress get remoteAddress => socket.remoteAddress;

  /// Les messages envoyés à partir de maintenant sont chiffrés.
  void encryptSending(SessionCipher cipher) => _sendCipher = cipher;

  /// Les messages reçus après le prochain message en clair de type [type] sont chiffrés.
  void encryptReceivingAfter(String type, SessionCipher cipher) => _armed = (type, cipher);

  /// Vrai quand les deux sens sont chiffrés.
  bool get encrypted => _sendCipher != null && _receiveCipher != null;

  void _onData(Uint8List data) {
    _buffer.add(data);
    if (_buffer.length > Limits.frameBytes + 4) {
      close();
      return;
    }
    var bytes = _buffer.takeBytes();
    while (bytes.length >= 4) {
      final length = ByteData.sublistView(bytes, 0, 4).getUint32(0);
      if (length > Limits.frameBytes) {
        close();
        return;
      }
      if (bytes.length < 4 + length) break;
      final frame = Uint8List.sublistView(bytes, 4, 4 + length);
      bytes = Uint8List.sublistView(bytes, 4 + length);
      // Les messages sont déchiffrés un par un, dans l'ordre d'arrivée.
      final copy = Uint8List.fromList(frame);
      _decoding = _decoding.then((_) => _decode(copy));
    }
    _buffer.add(bytes);
  }

  Future<void> _decode(Uint8List frame) async {
    if (_closed) return;
    try {
      final cipher = _receiveCipher;
      final clear = cipher == null ? frame : await cipher.open(frame);
      final json = jsonDecode(utf8.decode(clear));
      if (json is Map<String, dynamic> && json['type'] is String) {
        final armed = _armed;
        if (cipher == null && armed != null && json['type'] == armed.$1) {
          _receiveCipher = armed.$2;
          _armed = null;
        }
        if (!_incoming.isClosed) _incoming.add(json);
      } else {
        close();
      }
    } on Object {
      // Message illisible ou altéré : la liaison n'est plus digne de confiance.
      close();
    }
  }

  /// Envoie un message (chiffré si la liaison l'est).
  Future<void> send(Map<String, dynamic> message) {
    // Le chiffrement est décidé au moment de l'appel, pas au moment de l'envoi effectif.
    final cipher = _sendCipher;
    final done = _sending.then((_) async {
      if (_closed) return;
      final clear = utf8.encode(jsonEncode(message));
      final payload = cipher == null ? clear : await cipher.seal(clear);
      final header = ByteData(4)..setUint32(0, payload.length);
      try {
        socket.add([...header.buffer.asUint8List(), ...payload]);
      } on Object {
        close();
      }
    });
    _sending = done;
    return done;
  }

  /// Attend le prochain message, au plus [timeout].
  static Future<Map<String, dynamic>?> next(StreamIterator<Map<String, dynamic>> it, Duration timeout) async {
    try {
      return await it.moveNext().timeout(timeout) ? it.current : null;
    } on TimeoutException {
      return null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    // Pas d'attente : la fermeture n'aboutit que lorsque le lecteur a lu la fin du flux.
    if (!_incoming.isClosed) unawaited(_incoming.close());
    try {
      await socket.flush().timeout(const Duration(seconds: 1));
    } on Object {
      // Peu importe : la liaison se ferme.
    }
    socket.destroy();
  }
}

/// Encode et décode des octets dans les messages JSON.
String b64(List<int> bytes) => base64Encode(bytes);

List<int>? unb64(Object? value, {int? length}) {
  if (value is! String || value.length > 4096) return null;
  try {
    final bytes = base64Decode(value);
    if (length != null && bytes.length != length) return null;
    return bytes;
  } on FormatException {
    return null;
  }
}

/// Vrai pour un candidat WebRTC du réseau local : adresse privée de cet appareil (« host »)
/// ou nom mDNS en `.local`. Les autres sont ignorés : la transmission ne sort jamais du
/// réseau de la maison.
bool isLocalCandidate(String candidate) {
  final parts = candidate.trim().split(RegExp(r'\s+'));
  if (parts.length < 8 || !parts[0].startsWith('candidate:')) return false;
  final typeIndex = parts.indexOf('typ');
  if (typeIndex < 0 || typeIndex + 1 >= parts.length || parts[typeIndex + 1] != 'host') return false;
  final address = parts[4];
  if (address.endsWith('.local')) return true;
  final parsed = InternetAddress.tryParse(address);
  return parsed != null && isLocalAddress(parsed);
}

/// Comme [unb64], pour un morceau d'extrait (jusqu'à la taille d'un message).
List<int>? unb64Large(Object? value) {
  if (value is! String || value.length > Limits.frameBytes) return null;
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}
