import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'seasonal_simulation.dart';

/// Every seasonal sprite drawn once, in white, into one image.
///
/// A frame is then a single drawRawAtlas call, with each particle's color tinting its
/// sprite through BlendMode.modulate.
class SeasonalSpriteAtlas {
  SeasonalSpriteAtlas._(this.image, this.sheet);

  /// Draws the sprites at [devicePixelRatio] so they stay sharp on screen.
  factory SeasonalSpriteAtlas.build(double devicePixelRatio) {
    debugBuildCount++;
    final cell = (_logicalCell * devicePixelRatio).ceilToDouble();
    final stride = cell + _gutter * 2;
    final rows = (SeasonalSprite.count / _columns).ceil();
    final rects = Float32List(SeasonalSprite.count * 4);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < SeasonalSprite.count; i++) {
      final left = (i % _columns) * stride + _gutter;
      final top = (i ~/ _columns) * stride + _gutter;
      rects[i * 4] = left;
      rects[i * 4 + 1] = top;
      rects[i * 4 + 2] = left + cell;
      rects[i * 4 + 3] = top + cell;

      canvas.save();
      canvas.translate(left, top);
      canvas.scale(cell / _logicalCell);
      canvas.clipRect(const Rect.fromLTWH(0, 0, _logicalCell, _logicalCell));
      _drawSprite(canvas, i);
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (_columns * stride).ceil(),
      (rows * stride).ceil(),
    );
    picture.dispose();
    return SeasonalSpriteAtlas._(
      image,
      SeasonalSpriteSheet(rects: rects, cellSize: cell),
    );
  }

  static const _logicalCell = 32.0;
  static const _columns = 6;

  /// Transparent space around each cell, so filtering never samples a neighbour.
  static const _gutter = 2.0;

  static const _center = Offset(16, 16);
  static const _white = Color(0xFFFFFFFF);

  /// Modulated by the particle color, so a vein comes out as a darker shade of its leaf.
  static const _vein = Color(0xFFB0B0B0);

  @visibleForTesting
  static int debugBuildCount = 0;

  final ui.Image image;
  final SeasonalSpriteSheet sheet;

  void dispose() => image.dispose();

  static void _drawSprite(Canvas canvas, int sprite) {
    switch (sprite) {
      case SeasonalSprite.softDot:
        _radial(canvas, const [
          (0.0, 1.0),
          (0.3, 0.8),
          (0.6, 0.25),
          (1.0, 0.0),
        ]);
      case SeasonalSprite.glow:
        // A solid core with a short halo, so a spark still reads over a bright backdrop.
        _radial(canvas, const [
          (0.0, 1.0),
          (0.3, 0.95),
          (0.5, 0.5),
          (0.75, 0.12),
          (1.0, 0.0),
        ]);
      case SeasonalSprite.flake:
        _flake(canvas);
      case SeasonalSprite.leafOval:
        _leafOval(canvas);
      case SeasonalSprite.leafMaple:
        _leafMaple(canvas);
      default:
        final frame = sprite >= SeasonalSprite.confettiDisc
            ? sprite - SeasonalSprite.confettiDisc
            : sprite - SeasonalSprite.confettiStrip;
        final squash = math.max(
          0.12,
          frame / (SeasonalSprite.flipFrames - 1),
        );
        final paint = Paint()..color = _white;
        if (sprite >= SeasonalSprite.confettiDisc) {
          canvas.drawOval(
            Rect.fromCenter(center: _center, width: 14, height: 14 * squash),
            paint,
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: _center, width: 22, height: 12 * squash),
              const Radius.circular(1.5),
            ),
            paint,
          );
        }
    }
  }

  static void _radial(Canvas canvas, List<(double, double)> stops) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        _center,
        16,
        [for (final (_, alpha) in stops) _white.withValues(alpha: alpha)],
        [for (final (stop, _) in stops) stop],
      );
    canvas.drawCircle(_center, 16, paint);
  }

  static void _flake(Canvas canvas) {
    final paint = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    for (var arm = 0; arm < 6; arm++) {
      final angle = arm * math.pi / 3;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(_center, _center + direction * 13, paint);
      final branch = _center + direction * 7.5;
      for (final side in const [-1, 1]) {
        final a = angle + side * math.pi / 4;
        canvas.drawLine(
          branch,
          branch + Offset(math.cos(a), math.sin(a)) * 4.5,
          paint,
        );
      }
    }
    canvas.drawCircle(_center, 2, Paint()..color = _white);
  }

  static void _leafOval(Canvas canvas) {
    final body = Path()
      ..moveTo(16, 2)
      ..quadraticBezierTo(29, 12, 16, 28)
      ..quadraticBezierTo(3, 12, 16, 2)
      ..close();
    canvas.drawPath(body, Paint()..color = _white);
    canvas.drawLine(
      const Offset(16, 27),
      const Offset(16, 31),
      Paint()
        ..color = _white
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    final vein = Paint()
      ..color = _vein
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(16, 5), const Offset(16, 26), vein);
    for (var j = 0; j < 3; j++) {
      final y = 10.0 + j * 5;
      canvas.drawLine(Offset(16, y + 3), Offset(11, y), vein);
      canvas.drawLine(Offset(16, y + 3), Offset(21, y), vein);
    }
  }

  static void _leafMaple(Canvas canvas) {
    const lobeCenter = Offset(16, 15);
    final body = Path();
    for (var k = 0; k < 10; k++) {
      final angle = -math.pi / 2 + k * math.pi / 5;
      final radius = k.isEven ? 14.0 : 6.0;
      final point =
          lobeCenter + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (k == 0) {
        body.moveTo(point.dx, point.dy);
      } else {
        body.lineTo(point.dx, point.dy);
      }
    }
    body.close();
    // A fill plus a round-joined stroke of the same color softens the star into lobes.
    canvas.drawPath(body, Paint()..color = _white);
    canvas.drawPath(
      body,
      Paint()
        ..color = _white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      const Offset(16, 20),
      const Offset(16, 31),
      Paint()
        ..color = _white
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    final vein = Paint()
      ..color = _vein
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 5; k++) {
      final angle = -math.pi / 2 + k * 2 * math.pi / 5;
      canvas.drawLine(
        lobeCenter,
        lobeCenter + Offset(math.cos(angle), math.sin(angle)) * 11,
        vein,
      );
    }
  }
}
