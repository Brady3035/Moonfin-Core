import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The particle effects Home can draw. The names match the synced preference values.
enum SeasonalEffect { snow, fireworks, confetti, leaves }

/// How busy an effect is. The names match the synced preference values.
enum SeasonalDensity {
  light(particles: 30, bursts: 1),
  normal(particles: 60, bursts: 2),
  heavy(particles: 120, bursts: 3);

  const SeasonalDensity({required this.particles, required this.bursts});

  /// Most particles on screen at once for the falling effects.
  final int particles;

  /// Fireworks in the air at once, on average.
  final int bursts;
}

/// Cells in the sprite atlas, in the order the atlas draws them.
abstract final class SeasonalSprite {
  static const softDot = 0;
  static const flake = 1;
  static const leafOval = 2;
  static const leafMaple = 3;
  static const glow = 4;

  /// Confetti turns over by stepping through frames squashed on one axis, since the
  /// atlas transform can only scale both axes together.
  static const flipFrames = 6;
  static const confettiStrip = 5;
  static const confettiDisc = confettiStrip + flipFrames;

  static const count = confettiDisc + flipFrames;
}

/// Where each sprite sits in the atlas image.
class SeasonalSpriteSheet {
  const SeasonalSpriteSheet({required this.rects, required this.cellSize});

  /// Left, top, right and bottom of every sprite in image pixels.
  final Float32List rects;

  /// Edge of a square cell in image pixels. A sprite drawn [cellSize] wide in the image
  /// lands on screen at whatever logical size the particle asks for.
  final double cellSize;
}

enum SeasonalParticleKind { fall, rocket, spark, flash }

/// Particle state for one effect at one density.
///
/// Every random number is drawn when a particle spawns, and its position after that is a
/// closed-form function of its age. That keeps the motion the same at any frame rate.
class SeasonalSimulation {
  SeasonalSimulation(this.effect, this.density, {math.Random? random})
    : _random = random ?? math.Random(),
      capacity = effect == SeasonalEffect.fireworks
          ? (density.bursts + 2) * (_sparksPerBurst + 1)
          : density.particles {
    // The extra slot takes a spawn's draws when the pool is full, so the random sequence
    // stays the same whether or not the particle fits.
    final slots = capacity + 1;
    _kind = Uint8List(slots);
    _sprite = Uint8List(slots);
    _id = Int32List(slots);
    _seed = Int32List(slots);
    _color = Int32List(slots);
    _x0 = Float64List(slots);
    _y0 = Float64List(slots);
    _vx = Float64List(slots);
    _vy = Float64List(slots);
    _age = Float64List(slots);
    _life = Float64List(slots);
    _size = Float64List(slots);
    _alpha = Float64List(slots);
    _amp = Float64List(slots);
    _freq = Float64List(slots);
    _phase = Float64List(slots);
    _rot0 = Float64List(slots);
    _spin = Float64List(slots);
    _flip0 = Float64List(slots);
    _flipRate = Float64List(slots);
    _x = Float64List(slots);
    _y = Float64List(slots);
    _rot = Float64List(slots);
  }

  static const fadeInSeconds = 1.5;

  /// Longest step taken in one go, so a slow frame doesn't throw particles across the
  /// screen.
  static const maxStep = 0.05;

  /// A gap longer than this means the effect was away (a covered route, a paused app), so
  /// the step is skipped rather than replayed.
  static const resumeGap = 0.25;

  /// How far past an edge a particle may go before it's dropped.
  static const margin = 48.0;

  static const _sparksPerBurst = 36;
  static const _maxRockets = 6;
  static const _trail = 3;
  static const _sparkDrag = 1.8;

  static const _kindFall = 0;
  static const _kindRocket = 1;
  static const _kindSpark = 2;
  static const _kindFlash = 3;

  static const _leafColors = <int>[
    0xFFD2691E,
    0xFFB5451B,
    0xFFE08A1E,
    0xFFC9A227,
    0xFF8B4513,
    0xFFA63D20,
    0xFF7A8B2A,
  ];

  static const _confettiColors = <int>[
    0xFFE53935,
    0xFF1E88E5,
    0xFF43A047,
    0xFFFDD835,
    0xFFD81B60,
    0xFFFB8C00,
    0xFF8E24AA,
    0xFF00ACC1,
  ];

  static const _fireworkColors = <int>[
    0xFFFF5252,
    0xFFFFD740,
    0xFF69F0AE,
    0xFF40C4FF,
    0xFFE040FB,
    0xFFFF6E40,
    0xFFFFFFFF,
  ];

  final SeasonalEffect effect;
  final SeasonalDensity density;
  final int capacity;
  final math.Random _random;

  late final Uint8List _kind;
  late final Uint8List _sprite;
  late final Int32List _id;
  late final Int32List _seed;
  late final Int32List _color;
  late final Float64List _x0;
  late final Float64List _y0;
  late final Float64List _vx;

  /// Fall speed in pixels a second. For a rocket, the height where it bursts.
  late final Float64List _vy;
  late final Float64List _age;

  /// Seconds the particle lives. For a rocket, its flight time.
  late final Float64List _life;
  late final Float64List _size;
  late final Float64List _alpha;
  late final Float64List _amp;
  late final Float64List _freq;
  late final Float64List _phase;
  late final Float64List _rot0;
  late final Float64List _spin;
  late final Float64List _flip0;
  late final Float64List _flipRate;
  late final Float64List _x;
  late final Float64List _y;
  late final Float64List _rot;

  final _burstX = Float64List(_maxRockets);
  final _burstY = Float64List(_maxRockets);
  final _burstAge = Float64List(_maxRockets);
  final _burstSeed = Int32List(_maxRockets);
  final _burstColor = Int32List(_maxRockets);
  final _burstId = Int32List(_maxRockets);
  int _pendingBursts = 0;

  double _width = 0;
  double _height = 0;
  double _time = 0;
  double _spawnRate = 0;
  double _spawnDebt = 0;
  int _count = 0;
  int _rockets = 0;
  int _nextId = 0;

  /// Sprites [write] can emit at most, since a rocket draws a short trail behind it.
  int get outputCapacity =>
      capacity + (effect == SeasonalEffect.fireworks ? _maxRockets * _trail : 0);

  int get count => _count;

  double get time => _time;

  /// The falling effects aim for this many particles, a little under [capacity] so a
  /// burst of short-lived ones rarely finds the pool full.
  int get targetCount => (capacity * 0.9).round();

  /// Sets the area in logical pixels. A real change starts the effect over, filled.
  void resize(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) return;
    if ((width - _width).abs() < 1 && (height - _height).abs() < 1) return;
    _width = width;
    _height = height;
    _reseed();
  }

  /// Moves the effect on by [dt] seconds.
  void step(double dt) {
    if (_width <= 0 || dt <= 0 || dt > resumeGap) return;
    final step = math.min(dt, maxStep);
    _time += step;
    _pendingBursts = 0;

    var i = 0;
    while (i < _count) {
      final age = _age[i] += step;
      final kind = _kind[i];
      if (age >= _life[i]) {
        if (kind == _kindRocket) {
          _queueBurst(i, age - _life[i]);
          _rockets--;
        }
        _removeAt(i);
        continue;
      }
      _place(i);
      if (_offscreen(i)) {
        if (kind == _kindRocket) _rockets--;
        _removeAt(i);
        continue;
      }
      i++;
    }

    for (var b = 0; b < _pendingBursts; b++) {
      _burst(b);
    }

    _spawnDebt += step * _spawnRate;
    while (_spawnDebt >= 1) {
      _spawnDebt -= 1;
      // The leftover debt is how long ago this spawn was due.
      _spawn(_spawnDebt / _spawnRate);
    }
  }

  /// Fills the atlas arrays for the current frame and returns how many sprites to draw.
  /// The arrays must hold [outputCapacity] entries.
  int write(
    SeasonalSpriteSheet sheet,
    Float32List transforms,
    Float32List rects,
    Int32List colors,
  ) {
    final fade = math.min(1.0, _time / fadeInSeconds);
    var n = 0;
    for (var i = 0; i < _count; i++) {
      final age = _age[i];
      switch (_kind[i]) {
        case _kindFall:
          var sprite = _sprite[i];
          var color = _color[i];
          if (effect == SeasonalEffect.confetti) {
            final turn = math.cos(_flip0[i] + _flipRate[i] * age);
            sprite += (turn.abs() * (SeasonalSprite.flipFrames - 1)).round();
            if (turn < 0) color = _shade(color, 0.72);
          }
          n = _emit(n, sheet, transforms, rects, colors, sprite, _x[i], _y[i],
              _rot[i], _size[i], color, _alpha[i] * fade);
        case _kindRocket:
          n = _emit(n, sheet, transforms, rects, colors, SeasonalSprite.glow,
              _x[i], _y[i], 0, _size[i], _color[i], fade);
          for (var t = 1; t <= _trail; t++) {
            final past = age - t * 0.04;
            if (past <= 0) break;
            n = _emit(n, sheet, transforms, rects, colors, SeasonalSprite.glow,
                _x0[i] + _vx[i] * past, _rocketY(i, past), 0,
                _size[i] * (1 - 0.18 * t), _color[i], fade * (0.6 - 0.17 * t));
          }
        case _kindSpark:
          final u = age / _life[i];
          var alpha = _alpha[i] * math.pow(1 - u, 1.5);
          if (u > 0.55) alpha *= 0.6 + 0.4 * math.sin(age * 28 + _phase[i]);
          n = _emit(n, sheet, transforms, rects, colors, SeasonalSprite.glow,
              _x[i], _y[i], 0, _size[i] * (1 - 0.35 * u), _color[i],
              alpha * fade);
        case _kindFlash:
          final u = age / _life[i];
          n = _emit(n, sheet, transforms, rects, colors, SeasonalSprite.glow,
              _x[i], _y[i], 0, _size[i] * (0.6 + 0.4 * u), _color[i],
              _alpha[i] * (1 - u) * (1 - u) * fade);
      }
    }
    return n;
  }

  @visibleForTesting
  Iterable<({int id, SeasonalParticleKind kind, double x, double y})>
  get debugParticles sync* {
    for (var i = 0; i < _count; i++) {
      yield (
        id: _id[i],
        kind: SeasonalParticleKind.values[_kind[i]],
        x: _x[i],
        y: _y[i],
      );
    }
  }

  void _reseed() {
    _count = 0;
    _rockets = 0;
    _spawnDebt = 0;
    if (effect == SeasonalEffect.fireworks) {
      _spawnRate = density.bursts / 2.8;
      // One rocket per expected burst, already on its way up.
      for (var b = 0; b < density.bursts; b++) {
        final j = _count;
        _spawnRocket(j, 0);
        _age[j] = _life[j] * b / density.bursts;
        _id[j] = _nextId++;
        _place(j);
        _count++;
        _rockets++;
      }
      return;
    }

    final (slow, fast) = _fallRange;
    final meanLife =
        (1 + (margin + 10) / _height) * math.log(fast / slow) / (fast - slow);
    _spawnRate = targetCount / meanLife;
    // Start full, with each particle at a random point along its fall.
    for (var k = 0; k < targetCount; k++) {
      final j = _count;
      _spawnFalling(j, 0);
      _age[j] = _random.nextDouble() * _life[j];
      _id[j] = _nextId++;
      _place(j);
      _count++;
    }
  }

  /// Fall speed range in screen heights a second, from the farthest to the nearest.
  (double, double) get _fallRange => switch (effect) {
    SeasonalEffect.snow => (0.045, 0.10),
    SeasonalEffect.leaves => (0.035, 0.07),
    SeasonalEffect.confetti => (0.07, 0.13),
    SeasonalEffect.fireworks => (1, 1),
  };

  void _spawn(double age) {
    final fireworks = effect == SeasonalEffect.fireworks;
    final full =
        _count >= capacity || (fireworks && _rockets >= _maxRockets);
    final j = full ? capacity : _count;
    if (fireworks) {
      _spawnRocket(j, age);
    } else {
      _spawnFalling(j, age);
    }
    _id[j] = _nextId++;
    if (full) return;
    _place(j);
    _count++;
    if (fireworks) _rockets++;
  }

  void _spawnFalling(int j, double age) {
    final r = _random;
    // Depth ties size, speed and opacity together, so far particles are small, slow and
    // faint and near ones the opposite.
    final depth = r.nextDouble();
    final shape = r.nextDouble();
    final tint = r.nextDouble();
    final wobble = r.nextDouble();
    final drift = r.nextDouble() - 0.5;
    final (slow, fast) = _fallRange;

    var sprite = SeasonalSprite.softDot;
    var size = 0.0;
    var amp = 0.0;
    var freq = 0.0;
    var spin = 0.0;
    var alpha = 0.0;
    var color = 0xFFFFFFFF;
    var flipRate = 0.0;
    var driftScale = 0.0;
    switch (effect) {
      case SeasonalEffect.snow:
        final crystal = depth > 0.55 && shape < 0.45;
        sprite = crystal ? SeasonalSprite.flake : SeasonalSprite.softDot;
        size = crystal ? _lerp(9, 17, depth) : _lerp(4, 14, depth);
        amp = _lerp(4, 18, depth);
        freq = _lerp(0.5, 1.3, wobble);
        spin = (r.nextDouble() - 0.5) * 1.2;
        alpha = _lerp(0.35, 0.95, depth);
        color = tint < 0.25 ? 0xFFDDEEFF : 0xFFFFFFFF;
        driftScale = 0.02;
      case SeasonalEffect.leaves:
        sprite = shape < 0.5 ? SeasonalSprite.leafOval : SeasonalSprite.leafMaple;
        size = _lerp(14, 28, depth);
        amp = _lerp(18, 55, depth);
        freq = _lerp(0.9, 1.7, wobble);
        spin = (r.nextDouble() - 0.5) * 0.8;
        alpha = _lerp(0.7, 1.0, depth);
        color = _leafColors[(tint * _leafColors.length).floor()];
        driftScale = 0.03;
      case SeasonalEffect.confetti:
        sprite = shape < 0.6
            ? SeasonalSprite.confettiStrip
            : SeasonalSprite.confettiDisc;
        size = _lerp(7, 13, depth);
        amp = _lerp(6, 20, depth);
        freq = _lerp(1.5, 3.5, wobble);
        spin = (r.nextDouble() - 0.5) * 6;
        alpha = _lerp(0.85, 1.0, depth);
        color = _confettiColors[(tint * _confettiColors.length).floor()];
        flipRate = _lerp(4, 9, r.nextDouble());
        driftScale = 0.04;
      case SeasonalEffect.fireworks:
        break;
    }

    _kind[j] = _kindFall;
    _sprite[j] = sprite;
    _size[j] = size;
    _alpha[j] = alpha;
    _color[j] = color;
    _x0[j] = r.nextDouble() * _width;
    _y0[j] = -size;
    _vx[j] = drift * driftScale * _width;
    _vy[j] = _lerp(slow, fast, depth) * _height;
    _amp[j] = amp;
    _freq[j] = freq;
    _phase[j] = r.nextDouble() * 2 * math.pi;
    _rot0[j] = r.nextDouble() * 2 * math.pi;
    _spin[j] = spin;
    _flip0[j] = r.nextDouble() * 2 * math.pi;
    _flipRate[j] = flipRate;
    _life[j] = (_height + margin - _y0[j]) / _vy[j];
    _age[j] = age;
  }

  void _spawnRocket(int j, double age) {
    final r = _random;
    _kind[j] = _kindRocket;
    _x0[j] = _lerp(0.12, 0.88, r.nextDouble()) * _width;
    _y0[j] = _height + 8;
    _vy[j] = _lerp(0.12, 0.45, r.nextDouble()) * _height;
    _life[j] = _lerp(1.0, 1.5, r.nextDouble());
    _vx[j] = (r.nextDouble() - 0.5) * 0.04 * _width;
    _color[j] = _fireworkColors[r.nextInt(_fireworkColors.length)];
    _seed[j] = r.nextInt(1 << 30);
    _size[j] = 12;
    _age[j] = age;
  }

  void _queueBurst(int i, double age) {
    final b = _pendingBursts++;
    _burstX[b] = _x0[i] + _vx[i] * _life[i];
    _burstY[b] = _vy[i];
    _burstAge[b] = age;
    _burstSeed[b] = _seed[i];
    _burstColor[b] = _color[i];
    _burstId[b] = _id[i];
  }

  /// Each burst draws from its own seed, so the sparks come out the same whichever frame
  /// the rocket happens to burst in.
  void _burst(int b) {
    final r = math.Random(_burstSeed[b]);
    final radius =
        _lerp(0.2, 0.32, r.nextDouble()) * math.min(_width, _height);
    final speed = radius * _sparkDrag;
    final color = _burstColor[b];
    final second = r.nextDouble() < 0.35
        ? _fireworkColors[r.nextInt(_fireworkColors.length)]
        : color;
    final age = _burstAge[b];
    final idBase = -(_burstId[b] * 64);

    if (_count < capacity) {
      final j = _count++;
      _kind[j] = _kindFlash;
      _id[j] = idBase - 1;
      _x0[j] = _burstX[b];
      _y0[j] = _burstY[b];
      _size[j] = radius * 0.9;
      _alpha[j] = 0.3;
      _color[j] = 0xFFFFF4E0;
      _life[j] = 0.3;
      _age[j] = age;
      _place(j);
    }

    for (var k = 0; k < _sparksPerBurst && _count < capacity; k++) {
      final angle =
          2 * math.pi * k / _sparksPerBurst + (r.nextDouble() - 0.5) * 0.15;
      final v = speed * _lerp(0.7, 1.0, r.nextDouble());
      final pick = r.nextDouble();
      final j = _count++;
      _kind[j] = _kindSpark;
      _id[j] = idBase - 2 - k;
      _x0[j] = _burstX[b];
      _y0[j] = _burstY[b];
      _vx[j] = math.cos(angle) * v;
      _vy[j] = math.sin(angle) * v;
      _life[j] = _lerp(1.2, 1.9, r.nextDouble());
      _size[j] = _lerp(10, 15, r.nextDouble());
      _alpha[j] = 1;
      _phase[j] = r.nextDouble() * 2 * math.pi;
      _color[j] = pick < 0.2 ? 0xFFFFF6E5 : (pick < 0.6 ? color : second);
      _age[j] = age;
      _place(j);
    }
  }

  void _place(int i) {
    final age = _age[i];
    switch (_kind[i]) {
      case _kindFall:
        final swing = _freq[i] * age + _phase[i];
        _x[i] = _x0[i] + _vx[i] * age + _amp[i] * math.sin(swing);
        _y[i] = _y0[i] + _vy[i] * age;
        var rot = _rot0[i] + _spin[i] * age;
        // A leaf tilts into its swing, like a pendulum.
        if (effect == SeasonalEffect.leaves) rot += 0.6 * math.cos(swing);
        _rot[i] = rot;
      case _kindRocket:
        _x[i] = _x0[i] + _vx[i] * age;
        _y[i] = _rocketY(i, age);
      case _kindSpark:
        // Drag slows the spark toward a terminal fall speed. Solved exactly, so the arc
        // doesn't depend on how the frames slice it.
        final eased = (1 - math.exp(-_sparkDrag * age)) / _sparkDrag;
        final terminal = 0.22 * _height / _sparkDrag;
        _x[i] = _x0[i] + _vx[i] * eased;
        _y[i] = _y0[i] + terminal * age + (_vy[i] - terminal) * eased;
      case _kindFlash:
        _x[i] = _x0[i];
        _y[i] = _y0[i];
    }
  }

  /// A rocket slows as it climbs and stops at its burst height.
  double _rocketY(int i, double age) {
    final left = 1 - math.min(1.0, age / _life[i]);
    return _y0[i] + (_vy[i] - _y0[i]) * (1 - left * left);
  }

  bool _offscreen(int i) =>
      _x[i] < -margin ||
      _x[i] > _width + margin ||
      _y[i] < -margin ||
      _y[i] > _height + margin;

  void _removeAt(int i) {
    final last = --_count;
    if (i == last) return;
    _kind[i] = _kind[last];
    _sprite[i] = _sprite[last];
    _id[i] = _id[last];
    _seed[i] = _seed[last];
    _color[i] = _color[last];
    _x0[i] = _x0[last];
    _y0[i] = _y0[last];
    _vx[i] = _vx[last];
    _vy[i] = _vy[last];
    _age[i] = _age[last];
    _life[i] = _life[last];
    _size[i] = _size[last];
    _alpha[i] = _alpha[last];
    _amp[i] = _amp[last];
    _freq[i] = _freq[last];
    _phase[i] = _phase[last];
    _rot0[i] = _rot0[last];
    _spin[i] = _spin[last];
    _flip0[i] = _flip0[last];
    _flipRate[i] = _flipRate[last];
    _x[i] = _x[last];
    _y[i] = _y[last];
    _rot[i] = _rot[last];
  }

  static int _emit(
    int n,
    SeasonalSpriteSheet sheet,
    Float32List transforms,
    Float32List rects,
    Int32List colors,
    int sprite,
    double x,
    double y,
    double rotation,
    double size,
    int color,
    double alpha,
  ) {
    final scale = size / sheet.cellSize;
    final scos = scale * math.cos(rotation);
    final ssin = scale * math.sin(rotation);
    final anchor = sheet.cellSize / 2;
    final t = n * 4;
    transforms[t] = scos;
    transforms[t + 1] = ssin;
    transforms[t + 2] = x - scos * anchor + ssin * anchor;
    transforms[t + 3] = y - ssin * anchor - scos * anchor;
    final s = sprite * 4;
    rects[t] = sheet.rects[s];
    rects[t + 1] = sheet.rects[s + 1];
    rects[t + 2] = sheet.rects[s + 2];
    rects[t + 3] = sheet.rects[s + 3];
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    colors[n] = (a << 24) | (color & 0xFFFFFF);
    return n + 1;
  }

  static int _shade(int color, double factor) {
    final r = (((color >> 16) & 0xFF) * factor).round();
    final g = (((color >> 8) & 0xFF) * factor).round();
    final b = ((color & 0xFF) * factor).round();
    return (color & 0xFF000000) | (r << 16) | (g << 8) | b;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
