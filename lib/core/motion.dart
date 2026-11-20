import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Taille de la grille de luminosité comparée d'une image à l'autre (la même que dans
/// `CameraAnalyzer.kt` sur Android).
const gridWidth = 64;
const gridHeight = 48;

/// Écart de luminosité (sur 255) au-delà duquel un point a changé.
const pixelThreshold = 24;

/// Grille de luminosité d'une image PNG ou JPEG ; `null` si elle est illisible.
/// Pensée pour tourner dans un isolat (`compute`) : le décodage est coûteux.
Uint8List? luminanceGrid(Uint8List encoded) {
  final image = img.decodeImage(encoded);
  if (image == null || image.width == 0 || image.height == 0) return null;
  final grid = Uint8List(gridWidth * gridHeight);
  for (var gy = 0; gy < gridHeight; gy++) {
    final y = min(image.height - 1, gy * image.height ~/ gridHeight + image.height ~/ (2 * gridHeight));
    for (var gx = 0; gx < gridWidth; gx++) {
      final x = min(image.width - 1, gx * image.width ~/ gridWidth + image.width ~/ (2 * gridWidth));
      final p = image.getPixel(x, y);
      grid[gy * gridWidth + gx] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
    }
  }
  return grid;
}

/// Part des points qui ont changé entre deux grilles, une fois retiré le changement
/// global de luminosité (une lampe qu'on allume n'est pas un mouvement). Ce changement
/// global est la médiane des écarts : contrairement à la moyenne, un grand objet qui bouge
/// ne la fausse pas.
double motionBetween(Uint8List previous, Uint8List current) {
  if (previous.length != current.length || current.isEmpty) return 0;
  final diffs = Int16List(current.length);
  for (var i = 0; i < current.length; i++) {
    diffs[i] = current[i] - previous[i];
  }
  final sorted = Int16List.fromList(diffs)..sort();
  final median = sorted[sorted.length ~/ 2];
  var changed = 0;
  for (final d in diffs) {
    if ((d - median).abs() > pixelThreshold) changed++;
  }
  return changed / current.length;
}

/// Réencode une image (PNG de la capture) en JPEG pour le flux MJPEG. Pour un isolat.
Uint8List? toJpeg(Uint8List encoded) {
  final image = img.decodeImage(encoded);
  if (image == null) return null;
  return img.encodeJpg(image, quality: 75);
}
