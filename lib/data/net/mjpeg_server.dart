import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/crypto.dart';
import 'protocol.dart';

/// Nom d'utilisateur du flux MJPEG (le mot de passe est propre à chaque caméra).
const mjpegUser = 'scam';

/// Flux MJPEG local, pour sDash et Home Assistant, **désactivé par défaut**.
///
/// * `/video.mjpg` : image animée (deux images par seconde) ;
/// * `/image.jpg` : image fixe.
///
/// Protégé par un mot de passe (authentification HTTP « Basic », ou `?mdp=` dans
/// l'adresse) et réservé au réseau local. Ce flux n'est **pas chiffré** : contrairement à
/// l'image vue dans sCam, quelqu'un qui espionne le Wi-Fi pourrait le voir.
class MjpegServer {
  MjpegServer({required this.snapshot, required this.password, this.port = defaultMjpegPort, this.frameInterval});

  /// Dernière image JPEG de la caméra.
  final Future<Uint8List?> Function() snapshot;
  final String Function() password;
  final int port;
  final Duration? frameInterval;

  HttpServer? _server;
  int clients = 0;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  bool _authorized(HttpRequest request) {
    final expected = password();
    if (expected.isEmpty) return false;
    final query = request.uri.queryParameters['mdp'];
    if (query != null) return ScamCrypto.same(utf8.encode(query), utf8.encode(expected));
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Basic ')) return false;
    try {
      final decoded = utf8.decode(base64Decode(header.substring(6).trim()));
      return ScamCrypto.same(utf8.encode(decoded), utf8.encode('$mjpegUser:$expected'));
    } on Object {
      return false;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !isLocalAddress(remote)) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      if (!_authorized(request)) {
        response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="sCam"');
        await response.close();
        return;
      }
      switch (request.uri.path) {
        case '/image.jpg':
          final image = await snapshot();
          if (image == null) {
            response.statusCode = HttpStatus.serviceUnavailable;
          } else {
            response.headers
              ..contentType = ContentType('image', 'jpeg')
              ..set(HttpHeaders.cacheControlHeader, 'no-store');
            response.add(image);
          }
          await response.close();
        case '/video.mjpg':
          await _stream(response);
        default:
          response.statusCode = HttpStatus.notFound;
          await response.close();
      }
    } on Object {
      try {
        await response.close();
      } on Object {
        // Client parti.
      }
    }
  }

  Future<void> _stream(HttpResponse response) async {
    const boundary = 'scamimage';
    response.bufferOutput = false;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'multipart/x-mixed-replace; boundary=$boundary')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    clients++;
    try {
      while (_server != null) {
        final image = await snapshot();
        if (image != null) {
          response.add(
            ascii.encode('--$boundary\r\nContent-Type: image/jpeg\r\nContent-Length: ${image.length}\r\n\r\n'),
          );
          response.add(image);
          response.add(ascii.encode('\r\n'));
          await response.flush();
        }
        await Future<void>.delayed(frameInterval ?? const Duration(milliseconds: 500));
      }
    } finally {
      clients--;
      try {
        await response.close();
      } on Object {
        // Client parti.
      }
    }
  }
}
