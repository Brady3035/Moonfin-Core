import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/seasonal/seasonal_simulation.dart';

const _width = 1920.0;
const _height = 1080.0;

SeasonalSimulation _sim(
  SeasonalEffect effect,
  SeasonalDensity density, {
  int seed = 7,
}) =>
    SeasonalSimulation(effect, density, random: math.Random(seed))
      ..resize(_width, _height);

void _run(SeasonalSimulation sim, double seconds, double dt, [void Function()? each]) {
  final steps = (seconds / dt).round();
  for (var i = 0; i < steps; i++) {
    sim.step(dt);
    each?.call();
  }
}

void main() {
  group('bounds', () {
    for (final effect in SeasonalEffect.values) {
      for (final density in SeasonalDensity.values) {
        test('${effect.name} at ${density.name} stays on screen and under the cap', () {
          for (final seed in [1, 2, 3]) {
            final sim = _sim(effect, density, seed: seed);
            _run(sim, 60, 1 / 60, () {
              expect(sim.count, lessThanOrEqualTo(sim.capacity));
              for (final p in sim.debugParticles) {
                expect(p.y, greaterThanOrEqualTo(-SeasonalSimulation.margin));
                expect(p.y, lessThanOrEqualTo(_height + SeasonalSimulation.margin));
                expect(p.x, greaterThanOrEqualTo(-SeasonalSimulation.margin));
                expect(p.x, lessThanOrEqualTo(_width + SeasonalSimulation.margin));
              }
            });
          }
        });
      }
    }

    test('fireworks keeps bursting instead of filling up with sparks off the top', () {
      final sim = _sim(SeasonalEffect.fireworks, SeasonalDensity.normal);
      var sparksOnScreen = 0;
      var frames = 0;
      _run(sim, 60, 1 / 60, () {
        if (sim.time < 10) return;
        frames++;
        sparksOnScreen += sim.debugParticles
            .where((p) =>
                p.kind == SeasonalParticleKind.spark &&
                p.y >= 0 &&
                p.y <= _height)
            .length;
      });
      // Two bursts of 36 in the air on average, minus the gaps between them.
      expect(sparksOnScreen / frames, greaterThan(30));
    });
  });

  group('frame rate', () {
    for (final effect in SeasonalEffect.values) {
      test('${effect.name} lands in the same place at 60 Hz and 120 Hz', () {
        final at60 = _sim(effect, SeasonalDensity.normal);
        final at120 = _sim(effect, SeasonalDensity.normal);
        _run(at60, 3, 1 / 60);
        _run(at120, 3, 1 / 120);

        final positions = {
          for (final p in at120.debugParticles) p.id: (p.x, p.y),
        };
        var compared = 0;
        for (final p in at60.debugParticles) {
          final other = positions[p.id];
          if (other == null) continue;
          compared++;
          expect(p.x, closeTo(other.$1, 1e-3), reason: 'particle ${p.id} x');
          expect(p.y, closeTo(other.$2, 1e-3), reason: 'particle ${p.id} y');
        }
        expect(compared, greaterThan(0));
      });
    }

    test('a long gap is skipped rather than replayed', () {
      final sim = _sim(SeasonalEffect.snow, SeasonalDensity.normal);
      final before = {for (final p in sim.debugParticles) p.id: p.y};
      sim.step(0.3);
      expect(sim.time, 0);
      for (final p in sim.debugParticles) {
        expect(p.y, before[p.id]);
      }
    });

    test('a slow frame moves at most one capped step', () {
      final sim = _sim(SeasonalEffect.snow, SeasonalDensity.normal);
      sim.step(0.2);
      expect(sim.time, closeTo(SeasonalSimulation.maxStep, 1e-9));
    });
  });

  group('population', () {
    for (final effect in [
      SeasonalEffect.snow,
      SeasonalEffect.leaves,
      SeasonalEffect.confetti,
    ]) {
      for (final density in SeasonalDensity.values) {
        test('${effect.name} at ${density.name} starts full and stays near its target', () {
          final sim = _sim(effect, density);
          expect(sim.count, sim.targetCount);
          final ys = sim.debugParticles.map((p) => p.y).toList();
          expect(ys.reduce(math.min), lessThan(_height * 0.2));
          expect(ys.reduce(math.max), greaterThan(_height * 0.8));

          var total = 0;
          var frames = 0;
          _run(sim, 30, 1 / 60, () {
            total += sim.count;
            frames++;
          });
          expect(total / frames, closeTo(sim.targetCount, sim.targetCount * 0.15));
        });
      }
    }

    test('density scales the falling effects', () {
      expect(_sim(SeasonalEffect.snow, SeasonalDensity.light).targetCount, 27);
      expect(_sim(SeasonalEffect.snow, SeasonalDensity.normal).targetCount, 54);
      expect(_sim(SeasonalEffect.snow, SeasonalDensity.heavy).targetCount, 108);
    });
  });

  group('write', () {
    test('fades in, then draws every particle at full strength', () {
      final sim = _sim(SeasonalEffect.snow, SeasonalDensity.normal);
      final sheet = SeasonalSpriteSheet(
        rects: Float32List(SeasonalSprite.count * 4),
        cellSize: 64,
      );
      final transforms = Float32List(sim.outputCapacity * 4);
      final rects = Float32List(sim.outputCapacity * 4);
      final colors = Int32List(sim.outputCapacity);

      int maxAlpha() {
        final n = sim.write(sheet, transforms, rects, colors);
        expect(n, sim.count);
        return [
          for (var i = 0; i < n; i++) (colors[i] >> 24) & 0xFF,
        ].reduce(math.max);
      }

      expect(maxAlpha(), 0);
      _run(sim, SeasonalSimulation.fadeInSeconds + 0.1, 1 / 60);
      expect(maxAlpha(), greaterThan(200));
    });

    test('rockets draw a trail on top of their own sprite', () {
      final sim = _sim(SeasonalEffect.fireworks, SeasonalDensity.heavy);
      _run(sim, 0.5, 1 / 60);
      final sheet = SeasonalSpriteSheet(
        rects: Float32List(SeasonalSprite.count * 4),
        cellSize: 64,
      );
      final n = sim.write(
        sheet,
        Float32List(sim.outputCapacity * 4),
        Float32List(sim.outputCapacity * 4),
        Int32List(sim.outputCapacity),
      );
      expect(n, greaterThan(sim.count));
      expect(n, lessThanOrEqualTo(sim.outputCapacity));
    });
  });

  group('preference values', () {
    test("Smart-TV's old names map onto this set", () {
      expect(UserPreferences.normalizeSeasonalSurprise('winter'), 'snow');
      expect(UserPreferences.normalizeSeasonalSurprise('fall'), 'leaves');
      expect(UserPreferences.normalizeSeasonalSurprise('halloween'), 'none');
      expect(UserPreferences.normalizeSeasonalSurprise('Snow'), 'snow');
      expect(UserPreferences.normalizeSeasonalSurprise('aurora'), 'none');
      expect(UserPreferences.parseSeasonalSurprise('aurora'), isNull);
    });

    test('every value names an effect or none', () {
      for (final value in UserPreferences.seasonalSurpriseValues) {
        if (value == UserPreferences.seasonalNone) continue;
        expect(SeasonalEffect.values.asNameMap()[value], isNotNull, reason: value);
      }
      for (final value in UserPreferences.seasonalDensityValues) {
        expect(SeasonalDensity.values.asNameMap()[value], isNotNull, reason: value);
      }
      expect(UserPreferences.normalizeSeasonalDensity('blizzard'), 'normal');
    });
  });
}
