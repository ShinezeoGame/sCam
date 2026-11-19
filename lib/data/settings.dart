import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/crypto.dart';
import '../data/net/protocol.dart';
import '../models/camera.dart';

/// Thème de l'interface : automatique (suit le réglage du système), clair ou sombre.
enum AppThemeMode { auto, light, dark }

/// Un appareil appairé : une caméra (vue d'un écran) ou un écran (vu d'une caméra).
class PairedDevice {
  const PairedDevice({required this.id, required this.name, required this.key, this.address, this.port});

  final String id;
  final String name;

  /// Clé d'appairage (32 octets), propre à ce couple d'appareils.
  final List<int> key;

  /// Dernière adresse connue (caméras seulement) : l'écran s'y reconnecte même si les
  /// annonces ne passent pas.
  final String? address;
  final int? port;

  PairedDevice copyWith({String? name, String? address, int? port}) => PairedDevice(
    id: id,
    name: name ?? this.name,
    key: key,
    address: address ?? this.address,
    port: port ?? this.port,
  );

  Map<String, dynamic> toJson() => {'id': id, 'nom': name, 'cle': b64(key), 'adresse': ?address, 'port': ?port};

  static PairedDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['nom'], key = unb64(json['cle'], length: 32);
    if (id is! String || name is! String || key == null) return null;
    final address = json['adresse'], port = json['port'];
    return PairedDevice(
      id: id,
      name: name,
      key: key,
      address: address is String ? address : null,
      port: port is int ? port : null,
    );
  }
}

class Settings {
  const Settings({
    this.theme = AppThemeMode.auto,
    this.role,
    this.deviceId = '',
    this.deviceName = '',
    this.paired = const {},
    this.camera = const CameraSettings(),
    this.mjpegEnabled = false,
    this.mjpegPassword = '',
    this.background = true,
  });

  final AppThemeMode theme;

  /// Rôle de cet appareil ; `null` tant qu'il n'a pas été choisi.
  final DeviceRole? role;

  /// Identifiant de cet appareil, tiré au hasard à la première ouverture.
  final String deviceId;

  /// Nom de cet appareil (« Chambre de Léo » pour une caméra).
  final String deviceName;

  /// Appareils appairés, par identifiant.
  final Map<String, PairedDevice> paired;

  /// Réglages de la caméra (rôle caméra).
  final CameraSettings camera;

  /// Flux MJPEG local pour sDash et Home Assistant (désactivé par défaut).
  final bool mjpegEnabled;
  final String mjpegPassword;

  /// Écran : surveiller les alertes quand l'application est en arrière-plan (Android).
  final bool background;

  Settings copyWith({
    AppThemeMode? theme,
    DeviceRole? role,
    String? deviceId,
    String? deviceName,
    Map<String, PairedDevice>? paired,
    CameraSettings? camera,
    bool? mjpegEnabled,
    String? mjpegPassword,
    bool? background,
  }) => Settings(
    theme: theme ?? this.theme,
    role: role ?? this.role,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    paired: paired ?? this.paired,
    camera: camera ?? this.camera,
    mjpegEnabled: mjpegEnabled ?? this.mjpegEnabled,
    mjpegPassword: mjpegPassword ?? this.mjpegPassword,
    background: background ?? this.background,
  );
}

/// Identifiant ou mot de passe aléatoire, en chiffres hexadécimaux.
String randomHex([int bytes = 16]) =>
    [for (final b in ScamCrypto.random(bytes)) b.toRadixString(16).padLeft(2, '0')].join();

/// Lecture et écriture des réglages.
abstract class SettingsStore {
  Future<Settings> load();

  Future<void> save(Settings settings);
}

/// Réglages gardés en mémoire (tests).
class MemoryStore implements SettingsStore {
  MemoryStore([this.settings = const Settings()]);

  Settings settings;

  @override
  Future<Settings> load() async => settings;

  @override
  Future<void> save(Settings s) async => settings = s;
}

/// Réglages enregistrés sur l'appareil.
///
/// Les clés d'appairage y sont rangées comme le reste des réglages, dans l'espace privé de
/// l'application (inaccessible aux autres applications sur Android).
class DiskStore implements SettingsStore {
  @override
  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final paired = <String, PairedDevice>{};
    try {
      for (final raw in jsonDecode(prefs.getString('paired') ?? '[]') as List) {
        final device = PairedDevice.fromJson(raw);
        if (device != null) paired[device.id] = device;
      }
    } on Object {
      // Liste illisible : on repart sans appareil appairé.
    }
    Object? cameraJson;
    try {
      cameraJson = jsonDecode(prefs.getString('camera') ?? '{}');
    } on Object {
      cameraJson = null;
    }
    final themeName = prefs.getString('theme'), roleName = prefs.getString('role');
    return Settings(
      theme: AppThemeMode.values.firstWhere((m) => m.name == themeName, orElse: () => AppThemeMode.auto),
      role: DeviceRole.values.where((r) => r.name == roleName).firstOrNull,
      deviceId: prefs.getString('deviceId') ?? '',
      deviceName: prefs.getString('deviceName') ?? '',
      paired: paired,
      camera: CameraSettings.fromJson(cameraJson),
      mjpegEnabled: prefs.getBool('mjpegEnabled') ?? false,
      mjpegPassword: prefs.getString('mjpegPassword') ?? '',
      background: prefs.getBool('background') ?? true,
    );
  }

  @override
  Future<void> save(Settings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', s.theme.name);
    if (s.role != null) await prefs.setString('role', s.role!.name);
    await prefs.setString('deviceId', s.deviceId);
    await prefs.setString('deviceName', s.deviceName);
    await prefs.setString('paired', jsonEncode([for (final d in s.paired.values) d.toJson()]));
    await prefs.setString('camera', jsonEncode(s.camera.toJson()));
    await prefs.setBool('mjpegEnabled', s.mjpegEnabled);
    await prefs.setString('mjpegPassword', s.mjpegPassword);
    await prefs.setBool('background', s.background);
  }
}
