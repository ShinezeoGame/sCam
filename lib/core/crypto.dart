import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Outils cryptographiques de sCam.
///
/// * **Appairage** : échange de clés X25519 éphémères, précédé d'un engagement (l'écran
///   annonce l'empreinte de sa clé avant de voir celle de la caméra), puis code à six
///   chiffres affiché des deux côtés. Un intermédiaire qui voudrait se glisser entre les
///   deux appareils ne peut pas choisir ses clés pour retomber sur le même code : il a une
///   chance sur un million, et une seule tentative.
/// * **Connexion** : chaque appareil prouve qu'il connaît la clé d'appairage (HMAC sur deux
///   nombres aléatoires), puis tous les messages sont chiffrés (AES-256-GCM) avec une clé
///   de session tirée de la clé d'appairage et de ces deux nombres.
abstract final class ScamCrypto {
  static final _x25519 = X25519();
  static final _hmac = Hmac.sha256();
  static final _sha256 = Sha256();

  /// Octets aléatoires sûrs.
  static Uint8List random(int length) {
    final r = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < length; i++) r.nextInt(256)]);
  }

  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<List<int>> publicKeyOf(SimpleKeyPair pair) async => (await pair.extractPublicKey()).bytes;

  /// Empreinte qui engage l'écran sur sa clé publique avant qu'il ne voie celle de la caméra.
  static Future<List<int>> commitment(List<int> publicKey, List<int> nonce) async =>
      (await _sha256.hash([...utf8.encode('sCam engagement'), ...publicKey, ...nonce])).bytes;

  /// Clé d'appairage (32 octets) et code de vérification, identiques des deux côtés.
  static Future<({List<int> key, String code})> pairingSecret({
    required SimpleKeyPair own,
    required List<int> remotePublicKey,
    required List<int> screenPublicKey,
    required List<int> cameraPublicKey,
    required List<int> screenNonce,
    required List<int> cameraNonce,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: own,
      remotePublicKey: SimplePublicKey(remotePublicKey, type: KeyPairType.x25519),
    );
    final transcript = [...screenPublicKey, ...cameraPublicKey, ...screenNonce, ...cameraNonce];
    final key = await Hkdf(
      hmac: _hmac,
      outputLength: 32,
    ).deriveKey(secretKey: shared, nonce: transcript, info: utf8.encode('sCam appairage'));
    final digest = (await _sha256.hash([...utf8.encode('sCam code'), ...transcript])).bytes;
    return (key: await key.extractBytes(), code: verificationCode(digest));
  }

  /// Code à six chiffres tiré d'une empreinte.
  static String verificationCode(List<int> digest) {
    final value = (digest[0] << 24 | digest[1] << 16 | digest[2] << 8 | digest[3]) & 0x7fffffff;
    return (value % 1000000).toString().padLeft(6, '0');
  }

  /// Preuve de connaissance de la clé d'appairage, propre à un rôle et à une connexion.
  static Future<List<int>> proof(
    List<int> pairingKey,
    String role,
    List<int> screenNonce,
    List<int> cameraNonce,
  ) async {
    final mac = await _hmac.calculateMac([
      ...utf8.encode('sCam preuve $role'),
      ...screenNonce,
      ...cameraNonce,
    ], secretKey: SecretKey(pairingKey));
    return mac.bytes;
  }

  /// Clé de session d'une connexion.
  static Future<SecretKey> sessionKey(List<int> pairingKey, List<int> screenNonce, List<int> cameraNonce) async {
    final key = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
      secretKey: SecretKey(pairingKey),
      nonce: [...screenNonce, ...cameraNonce],
      info: utf8.encode('sCam session'),
    );
    return SecretKey(await key.extractBytes());
  }

  /// Comparaison en temps constant.
  static bool same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Chiffrement des messages d'une connexion établie.
///
/// Chaque sens a son propre compteur, inscrit dans le nonce : un message rejoué, retiré ou
/// réordonné est refusé.
class SessionCipher {
  SessionCipher(this._key, {required bool isScreen}) : _sendTag = isScreen ? 1 : 2, _receiveTag = isScreen ? 2 : 1;

  final SecretKey _key;
  final int _sendTag;
  final int _receiveTag;
  int _sent = 0;
  int _received = 0;

  static final _aes = AesGcm.with256bits();

  List<int> _nonce(int tag, int counter) {
    final nonce = Uint8List(12);
    nonce[0] = tag;
    ByteData.sublistView(nonce).setUint64(4, counter);
    return nonce;
  }

  Future<Uint8List> seal(List<int> clear) async {
    final box = await _aes.encrypt(clear, secretKey: _key, nonce: _nonce(_sendTag, _sent++));
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  /// Déchiffre le message suivant ; lève une exception s'il a été altéré ou rejoué.
  Future<List<int>> open(List<int> sealed) async {
    if (sealed.length < 16) throw const FormatException('Message chiffré trop court');
    final box = SecretBox(
      sealed.sublist(0, sealed.length - 16),
      nonce: _nonce(_receiveTag, _received),
      mac: Mac(sealed.sublist(sealed.length - 16)),
    );
    final clear = await _aes.decrypt(box, secretKey: _key);
    _received++;
    return clear;
  }
}
