/// Objectif utilisé par la caméra.
enum Lens {
  back('Arrière'),
  front('Avant');

  const Lens(this.label);

  final String label;
}

/// Qualité de l'image envoyée.
enum Quality {
  low('Économe', 640, 360),
  medium('Normale', 960, 540),
  high('Haute', 1280, 720);

  const Quality(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;
}

/// Genre d'alerte.
enum AlertKind {
  noise('Bruit'),
  motion('Mouvement');

  const AlertKind(this.label);

  final String label;
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

double _unit(Object? value, double fallback) => value is num ? value.toDouble().clamp(0.0, 1.0) : fallback;

/// Réglages d'une caméra. Ils sont gardés sur la caméra et modifiables depuis tout écran
/// appairé : tous les écrans reçoivent ainsi les mêmes alertes.
class CameraSettings {
  const CameraSettings({
    this.lens = Lens.back,
    this.quality = Quality.medium,
    this.torch = false,
    this.noiseAlert = true,
    this.noiseThreshold = 0.55,
    this.motionAlert = false,
    this.motionSensitivity = 0.5,
    this.recordClips = true,
  });

  final Lens lens;
  final Quality quality;

  /// Lampe du téléphone allumée.
  final bool torch;

  final bool noiseAlert;

  /// Niveau sonore (0 à 1, voir `soundLevelFromDb`) au-delà duquel le bruit alerte.
  final double noiseThreshold;

  final bool motionAlert;

  /// 0 : seuls les grands mouvements alertent ; 1 : le moindre changement.
  final double motionSensitivity;

  /// Enregistrer un extrait (les 30 secondes qui suivent) à chaque alerte, sur la caméra.
  final bool recordClips;

  CameraSettings copyWith({
    Lens? lens,
    Quality? quality,
    bool? torch,
    bool? noiseAlert,
    double? noiseThreshold,
    bool? motionAlert,
    double? motionSensitivity,
    bool? recordClips,
  }) => CameraSettings(
    lens: lens ?? this.lens,
    quality: quality ?? this.quality,
    torch: torch ?? this.torch,
    noiseAlert: noiseAlert ?? this.noiseAlert,
    noiseThreshold: noiseThreshold ?? this.noiseThreshold,
    motionAlert: motionAlert ?? this.motionAlert,
    motionSensitivity: motionSensitivity ?? this.motionSensitivity,
    recordClips: recordClips ?? this.recordClips,
  );

  Map<String, dynamic> toJson() => {
    'objectif': lens.name,
    'qualite': quality.name,
    'lampe': torch,
    'alerteBruit': noiseAlert,
    'seuilBruit': noiseThreshold,
    'alerteMouvement': motionAlert,
    'sensibiliteMouvement': motionSensitivity,
    'extraits': recordClips,
  };

  static CameraSettings fromJson(Object? json, [CameraSettings base = const CameraSettings()]) {
    if (json is! Map) return base;
    return CameraSettings(
      lens: _enum(Lens.values, json['objectif'], base.lens),
      quality: _enum(Quality.values, json['qualite'], base.quality),
      torch: json['lampe'] is bool ? json['lampe'] as bool : base.torch,
      noiseAlert: json['alerteBruit'] is bool ? json['alerteBruit'] as bool : base.noiseAlert,
      noiseThreshold: _unit(json['seuilBruit'], base.noiseThreshold),
      motionAlert: json['alerteMouvement'] is bool ? json['alerteMouvement'] as bool : base.motionAlert,
      motionSensitivity: _unit(json['sensibiliteMouvement'], base.motionSensitivity),
      recordClips: json['extraits'] is bool ? json['extraits'] as bool : base.recordClips,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CameraSettings &&
      other.lens == lens &&
      other.quality == quality &&
      other.torch == torch &&
      other.noiseAlert == noiseAlert &&
      other.noiseThreshold == noiseThreshold &&
      other.motionAlert == motionAlert &&
      other.motionSensitivity == motionSensitivity &&
      other.recordClips == recordClips;

  @override
  int get hashCode => Object.hash(lens, quality, torch, noiseAlert, noiseThreshold, motionAlert, motionSensitivity);
}

/// État d'une caméra, envoyé régulièrement aux écrans.
class CameraStatus {
  const CameraStatus({
    required this.name,
    this.running = false,
    this.battery,
    this.charging = false,
    this.temperature,
    this.hot = false,
    this.sound = 0,
    this.motion = 0,
    this.viewers = 0,
    this.hasTorch = false,
    this.canSwitchLens = true,
    this.canRecord = false,
    this.recording = false,
    this.settings = const CameraSettings(),
  });

  final String name;

  /// Vrai quand la caméra filme.
  final bool running;

  /// Charge de la batterie, en pourcentage.
  final int? battery;
  final bool charging;

  /// Température de la batterie, en degrés.
  final double? temperature;

  /// Le système signale que le téléphone chauffe.
  final bool hot;

  /// Niveau sonore actuel (0 à 1).
  final double sound;

  /// Part de l'image qui vient de changer (0 à 1).
  final double motion;

  /// Écrans qui regardent en ce moment.
  final int viewers;

  final bool hasTorch;

  /// Objectif avant et arrière (téléphone) ; faux pour une webcam.
  final bool canSwitchLens;

  /// La caméra sait enregistrer des extraits (Android).
  final bool canRecord;

  /// Un extrait est en cours d'enregistrement.
  final bool recording;
  final CameraSettings settings;

  Map<String, dynamic> toJson() => {
    'nom': name,
    'active': running,
    'batterie': ?battery,
    'enCharge': charging,
    'temperature': ?temperature,
    'chaud': hot,
    'son': sound,
    'mouvement': motion,
    'spectateurs': viewers,
    'aLampe': hasTorch,
    'objectifs': canSwitchLens,
    'enregistre': canRecord,
    'enregistrement': recording,
    'reglages': settings.toJson(),
  };

  static CameraStatus? fromJson(Object? json) {
    if (json is! Map || json['nom'] is! String) return null;
    final battery = json['batterie'], temperature = json['temperature'], viewers = json['spectateurs'];
    return CameraStatus(
      name: json['nom'] as String,
      running: json['active'] == true,
      battery: battery is int ? battery.clamp(0, 100) : null,
      charging: json['enCharge'] == true,
      temperature: temperature is num ? temperature.toDouble() : null,
      hot: json['chaud'] == true,
      sound: _unit(json['son'], 0),
      motion: _unit(json['mouvement'], 0),
      viewers: viewers is int ? viewers : 0,
      hasTorch: json['aLampe'] == true,
      canSwitchLens: json['objectifs'] != false,
      canRecord: json['enregistre'] == true,
      recording: json['enregistrement'] == true,
      settings: CameraSettings.fromJson(json['reglages']),
    );
  }
}

/// Une alerte levée par une caméra.
class CameraAlert {
  const CameraAlert({required this.cameraId, required this.cameraName, required this.kind, required this.at});

  final String cameraId;
  final String cameraName;
  final AlertKind kind;
  final DateTime at;
}

/// Un extrait enregistré sur la caméra après une alerte.
class CameraClip {
  const CameraClip({required this.id, required this.at, required this.kind, required this.bytes});

  /// Nom du fichier sur la caméra (« 20261120-224105-bruit.mp4 »).
  final String id;
  final DateTime at;
  final AlertKind kind;
  final int bytes;

  static final _name = RegExp(r'^(\d{8})-(\d{6})-(bruit|mouvement)\.mp4$');

  /// Lit le nom d'un fichier d'extrait ; `null` s'il n'en est pas un.
  static CameraClip? fromFile(String name, int bytes) {
    final m = _name.firstMatch(name);
    if (m == null) return null;
    final d = m.group(1)!, t = m.group(2)!;
    final at = DateTime(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(4, 6)),
      int.parse(d.substring(6, 8)),
      int.parse(t.substring(0, 2)),
      int.parse(t.substring(2, 4)),
      int.parse(t.substring(4, 6)),
    );
    return CameraClip(id: name, at: at, kind: m.group(3) == 'bruit' ? AlertKind.noise : AlertKind.motion, bytes: bytes);
  }

  /// Nom de fichier d'un nouvel extrait.
  static String fileName(DateTime at, AlertKind kind) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}${two(at.second)}-'
        '${kind == AlertKind.noise ? 'bruit' : 'mouvement'}.mp4';
  }

  Map<String, dynamic> toJson() => {'id': id, 'taille': bytes};

  static CameraClip? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['taille'] is! int) return null;
    return fromFile(json['id'] as String, json['taille'] as int);
  }
}

/// Convertit un niveau en décibels pleine échelle (−90 à 0) en niveau de 0 à 1 :
/// −70 dB (silence d'une chambre) donne 0, 0 dB (saturation) donne 1.
double soundLevelFromDb(double db) => ((db + 70) / 70).clamp(0.0, 1.0);
