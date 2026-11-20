import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../core/crypto.dart';
import '../settings.dart';
import 'protocol.dart';

/// Échec d'un appairage ou d'une connexion, avec un message pour l'utilisateur.
class LinkException implements Exception {
  const LinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un appairage en cours, des deux côtés : le code à comparer, puis la confirmation de
/// chacun. L'appairage n'est conclu que si les deux appareils confirment.
class PairingExchange {
  PairingExchange._(
    this._link,
    this._it, {
    required this.peerId,
    required this.peerName,
    required this.code,
    required this.key,
  }) {
    _timeout = Timer(Limits.pairingTimeout, () => _finish(null, 'Le délai d\'appairage est dépassé.'));
  }

  final MessageLink _link;
  final StreamIterator<Map<String, dynamic>> _it;
  final String peerId;
  final String peerName;

  /// Code à six chiffres, affiché sur les deux écrans.
  final String code;

  /// Clé d'appairage tirée de l'échange (gardée une fois les deux confirmations reçues).
  final List<int> key;
  late final Timer _timeout;
  final _result = Completer<PairedDevice?>();
  bool? _ownAnswer;
  bool _peerConfirmed = false;
  String? failure;

  /// Appareil appairé, ou `null` si l'un des deux a refusé (voir [failure]).
  Future<PairedDevice?> get result => _result.future;

  InternetAddress get remoteAddress => _link.remoteAddress;

  void _listen() async {
    while (await _it.moveNext()) {
      final message = _it.current;
      if (message['type'] == 'confirme') {
        if (message['ok'] != true) {
          _finish(null, 'L\'appairage a été refusé sur l\'autre appareil.');
          return;
        }
        _peerConfirmed = true;
        _check();
      }
    }
    if (!_result.isCompleted) _finish(null, 'La liaison a été coupée pendant l\'appairage.');
  }

  /// Réponse de l'utilisateur : les codes sont-ils identiques ?
  Future<void> answer(bool same) async {
    if (_result.isCompleted || _ownAnswer != null) return;
    _ownAnswer = same;
    await _link.send({'type': 'confirme', 'ok': same});
    if (!same) {
      _finish(null, 'Appairage annulé.');
    } else {
      _check();
    }
  }

  void _check() {
    if (_ownAnswer == true && _peerConfirmed) {
      _finish(PairedDevice(id: peerId, name: peerName, key: key), null);
    }
  }

  void _finish(PairedDevice? device, String? error) {
    if (_result.isCompleted) return;
    failure = error;
    _timeout.cancel();
    _result.complete(device);
    // Laisse partir la dernière confirmation avant de fermer.
    Future<void>.delayed(const Duration(milliseconds: 300), _link.close);
  }

  Future<void> cancel() => answer(false);

  /// Côté écran : se connecte à la caméra et ouvre l'appairage.
  static Future<PairingExchange> requestFromScreen({
    required InternetAddress address,
    required int port,
    required String selfId,
    required String selfName,
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: const Duration(seconds: 6));
    } on Object {
      throw const LinkException('La caméra ne répond pas. Vérifiez qu\'elle est allumée, sur le même Wi-Fi.');
    }
    final link = MessageLink(socket);
    final it = StreamIterator(link.messages);
    try {
      final pair = await ScamCrypto.newKeyPair();
      final ownKey = await ScamCrypto.publicKeyOf(pair);
      final nonce = ScamCrypto.random(16);
      await link.send({
        'type': 'appairage',
        'id': selfId,
        'nom': selfName,
        'engagement': b64(await ScamCrypto.commitment(ownKey, nonce)),
      });
      final reply = await MessageLink.next(it, const Duration(seconds: 30));
      if (reply == null) throw const LinkException('La caméra ne répond pas.');
      if (reply['type'] == 'refus') {
        throw const LinkException(
          'L\'appairage n\'est pas ouvert sur la caméra. Touchez « Appairer un écran » sur celle-ci.',
        );
      }
      final cameraKey = unb64(reply['cle'], length: 32), cameraNonce = unb64(reply['alea'], length: 16);
      final cameraId = reply['id'], cameraName = reply['nom'];
      if (reply['type'] != 'cle' ||
          cameraKey == null ||
          cameraNonce == null ||
          cameraId is! String ||
          cameraName is! String) {
        throw const LinkException('Réponse inattendue de la caméra.');
      }
      await link.send({'type': 'revele', 'cle': b64(ownKey), 'alea': b64(nonce)});
      final secret = await ScamCrypto.pairingSecret(
        own: pair,
        remotePublicKey: cameraKey,
        screenPublicKey: ownKey,
        cameraPublicKey: cameraKey,
        screenNonce: nonce,
        cameraNonce: cameraNonce,
      );
      return PairingExchange._(link, it, peerId: cameraId, peerName: cameraName, code: secret.code, key: secret.key)
        .._listen();
    } catch (_) {
      await link.close();
      rethrow;
    }
  }

  /// Côté caméra : poursuit un appairage demandé par un écran (premier message déjà lu).
  static Future<PairingExchange?> answerOnCamera({
    required MessageLink link,
    required StreamIterator<Map<String, dynamic>> it,
    required Map<String, dynamic> request,
    required String selfId,
    required String selfName,
  }) async {
    final screenId = request['id'], screenName = request['nom'];
    final commitment = unb64(request['engagement'], length: 32);
    if (screenId is! String || screenId.isEmpty || screenId.length > 64) return null;
    if (screenName is! String || screenName.length > 80 || commitment == null) return null;
    final SimpleKeyPair pair = await ScamCrypto.newKeyPair();
    final ownKey = await ScamCrypto.publicKeyOf(pair);
    final nonce = ScamCrypto.random(16);
    await link.send({'type': 'cle', 'id': selfId, 'nom': selfName, 'cle': b64(ownKey), 'alea': b64(nonce)});
    final reveal = await MessageLink.next(it, const Duration(seconds: 30));
    if (reveal == null || reveal['type'] != 'revele') return null;
    final screenKey = unb64(reveal['cle'], length: 32), screenNonce = unb64(reveal['alea'], length: 16);
    if (screenKey == null || screenNonce == null) return null;
    // L'écran doit révéler exactement la clé sur laquelle il s'était engagé.
    if (!ScamCrypto.same(await ScamCrypto.commitment(screenKey, screenNonce), commitment)) return null;
    final secret = await ScamCrypto.pairingSecret(
      own: pair,
      remotePublicKey: screenKey,
      screenPublicKey: screenKey,
      cameraPublicKey: ownKey,
      screenNonce: screenNonce,
      cameraNonce: nonce,
    );
    return PairingExchange._(
      link,
      it,
      peerId: screenId,
      peerName: screenName.trim(),
      code: secret.code,
      key: secret.key,
    ).._listen();
  }
}

/// Connexion d'un écran appairé : chaque appareil prouve qu'il connaît la clé
/// d'appairage, puis la liaison est chiffrée dans les deux sens.
abstract final class Handshake {
  /// Côté écran. Renvoie la liaison chiffrée et son lecteur de messages.
  static Future<(MessageLink, StreamIterator<Map<String, dynamic>>)> connect({
    required InternetAddress address,
    required int port,
    required String selfId,
    required PairedDevice camera,
  }) async {
    final socket = await Socket.connect(address, port, timeout: const Duration(seconds: 5));
    final link = MessageLink(socket);
    final it = StreamIterator(link.messages);
    try {
      final screenNonce = ScamCrypto.random(16);
      await link.send({'type': 'bonjour', 'id': selfId, 'alea': b64(screenNonce)});
      final challenge = await MessageLink.next(it, Limits.handshakeTimeout);
      if (challenge == null) throw const LinkException('La caméra ne répond pas.');
      if (challenge['type'] == 'refus') {
        throw const LinkException('Cette caméra ne reconnaît plus cet écran : appairez-les de nouveau.');
      }
      final cameraNonce = unb64(challenge['alea'], length: 16), proof = unb64(challenge['preuve'], length: 32);
      if (challenge['type'] != 'defi' || cameraNonce == null || proof == null) {
        throw const LinkException('Réponse inattendue de la caméra.');
      }
      final expected = await ScamCrypto.proof(camera.key, 'camera', screenNonce, cameraNonce);
      if (!ScamCrypto.same(expected, proof)) {
        throw const LinkException('Cette caméra n\'est pas celle qui a été appairée.');
      }
      final key = await ScamCrypto.sessionKey(camera.key, screenNonce, cameraNonce);
      final cipher = SessionCipher(key, isScreen: true);
      await link.send({
        'type': 'preuve',
        'preuve': b64(await ScamCrypto.proof(camera.key, 'ecran', screenNonce, cameraNonce)),
      });
      link
        ..encryptSending(cipher)
        ..encryptReceivingAfter('pret', cipher);
      final ready = await MessageLink.next(it, Limits.handshakeTimeout);
      if (ready == null || ready['type'] != 'pret') throw const LinkException('La caméra a refusé la connexion.');
      return (link, it);
    } catch (_) {
      await link.close();
      rethrow;
    }
  }

  /// Côté caméra, après un « bonjour ». Renvoie l'écran reconnu, ou `null` (liaison fermée).
  static Future<PairedDevice?> accept({
    required MessageLink link,
    required StreamIterator<Map<String, dynamic>> it,
    required Map<String, dynamic> hello,
    required PairedDevice? Function(String id) lookup,
  }) async {
    final id = hello['id'], screenNonce = unb64(hello['alea'], length: 16);
    final screen = id is String ? lookup(id) : null;
    if (screen == null || screenNonce == null) {
      await link.send({'type': 'refus'});
      await link.close();
      return null;
    }
    final cameraNonce = ScamCrypto.random(16);
    final cipher = SessionCipher(await ScamCrypto.sessionKey(screen.key, screenNonce, cameraNonce), isScreen: false);
    link.encryptReceivingAfter('preuve', cipher);
    await link.send({
      'type': 'defi',
      'alea': b64(cameraNonce),
      'preuve': b64(await ScamCrypto.proof(screen.key, 'camera', screenNonce, cameraNonce)),
    });
    final answer = await MessageLink.next(it, Limits.handshakeTimeout);
    final proof = answer == null ? null : unb64(answer['preuve'], length: 32);
    final expected = await ScamCrypto.proof(screen.key, 'ecran', screenNonce, cameraNonce);
    if (answer?['type'] != 'preuve' || proof == null || !ScamCrypto.same(proof, expected)) {
      await link.close();
      return null;
    }
    await link.send({'type': 'pret'});
    link.encryptSending(cipher);
    return screen;
  }
}
