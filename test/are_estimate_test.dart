import 'package:flutter_test/flutter_test.dart';
import 'package:reedlab/models/cane.dart';
import 'package:reedlab/services/are_estimate.dart';

CaneSample _sample({
  required double mass,
  required double flex,
  required double freq,
  double length = 120.0,
  double width = 14.0,
  double thickness = 3.0,
  double? submergedLengthMm,
  double? hardness,
}) {
  return CaneSample(
    id: 'test',
    createdAt: DateTime(2026, 1, 1),
    sampleName: 'test',
    purchaseDate: DateTime(2026, 1, 1),
    source: 'test',
    lengthMm: length,
    widthMm: width,
    thicknessMm: thickness,
    massG: mass,
    flexibilityDeg: flex,
    loadG: 200,
    naturalFrequencyHz: freq,
    submergedLengthMm: submergedLengthMm,
    hardness: hardness,
  );
}

void main() {
  const estimator = AreEstimator();

  group('AreEstimator', () {
    test('estimate reproduces real ARE on QA reference samples', () {
      // Real QA samples that happen to have a Flexter flexibility reading, so
      // we can check the Flexter-free estimate against the true ARE.
      final samples = <CaneSample>[
        _sample(mass: 0.72, flex: 20.8, freq: 1220.4, submergedLengthMm: 98),
        _sample(mass: 0.69, flex: 22.1, freq: 1174.8, submergedLengthMm: 96),
        _sample(mass: 0.75, flex: 18.6, freq: 1305.6, submergedLengthMm: 99),
        _sample(mass: 0.67, flex: 24.0, freq: 1128.2, submergedLengthMm: 95),
      ];

      for (final sample in samples) {
        final realAre = sample.ari;
        final estimate = estimator.estimate(sample);
        expect(realAre, isNotNull);
        expect(estimate.isAvailable, isTrue);
        // Within one ARE band (< 1.5) of the true value.
        expect(
          (estimate.estimatedAre! - realAre!).abs(),
          lessThan(1.5),
          reason: 'estimate should land near the true ARE',
        );
      }
    });

    test('stiffer cane (heavier, higher pitch) estimates less flexibility', () {
      // Flexibility (twist under load) is the term we reconstruct: stiffer cane
      // twists less. ARE itself also depends on pitch, so it is not monotonic
      // in stiffness alone.
      final soft = estimator.estimate(_sample(mass: 0.67, flex: 0, freq: 1128.2));
      final stiff = estimator.estimate(_sample(mass: 0.75, flex: 0, freq: 1305.6));
      expect(stiff.estimatedFlexibilityDeg, lessThan(soft.estimatedFlexibilityDeg!));
      expect(stiff.stiffnessIndex, greaterThan(soft.stiffnessIndex!));
    });

    test('is unavailable without tap-tone or size', () {
      final noTap = estimator.estimate(_sample(mass: 0.7, flex: 0, freq: 0));
      expect(noTap.isAvailable, isFalse);
    });

    test('confidence rises with more corroborating signals', () {
      final core = estimator.estimate(
        _sample(mass: 0, flex: 0, freq: 1210),
      );
      final withMass = estimator.estimate(
        _sample(mass: 0.70, flex: 0, freq: 1210),
      );
      final withMassAndFloat = estimator.estimate(
        _sample(mass: 0.70, flex: 0, freq: 1210, submergedLengthMm: 98),
      );
      expect(core.confidence, AreEstimateConfidence.low);
      expect(withMass.confidence, AreEstimateConfidence.medium);
      expect(withMassAndFloat.confidence, AreEstimateConfidence.high);
    });

    test('exposes the full signal checklist in display order', () {
      final estimate = estimator.estimate(
        _sample(mass: 0.70, flex: 0, freq: 1210, hardness: 42),
      );
      expect(
        estimate.signals.map((signal) => signal.kind).toList(),
        AreSignalKind.values,
      );
      // tap-tone + size + weight + hardness present; float test missing. The
      // strength meter ignores the Flexter flexibility signal.
      expect(estimate.signalsPresentCount, 4);
      expect(estimate.estimateSignals.length, 5);
      expect(estimate.essentialsComplete, isTrue);
      final floatSignal = estimate.signals
          .firstWhere((signal) => signal.kind == AreSignalKind.floatTest);
      expect(floatSignal.present, isFalse);
    });

    test('flexibility is a true-ARE signal, separate from the strength meter', () {
      final kind = AreSignalKind.flexibility;
      expect(kind.role, AreSignalRole.trueAre);
      expect(kind.isEssential, isFalse);

      // With a Flexter flexibility reading the real ARE is available, and the
      // flexibility signal is marked present without inflating the meter.
      final measured =
          estimator.estimate(_sample(mass: 0.70, flex: 21, freq: 1210));
      expect(measured.trueAreSignals.single.present, isTrue);
      expect(measured.trueAreSignals.single.kind, AreSignalKind.flexibility);
      // Meter counts tap-tone + size + weight = 3, not the flexibility reading.
      expect(measured.signalsPresentCount, 3);

      // Without it, the simulated estimate still works and flexibility is shown
      // as the outstanding upgrade.
      final simulated =
          estimator.estimate(_sample(mass: 0.70, flex: 0, freq: 1210));
      expect(simulated.isAvailable, isTrue);
      expect(simulated.trueAreSignals.single.present, isFalse);
    });

    test('checklist still tracks signals while the estimate is locked', () {
      // No tap-tone: estimate is unavailable, but the checklist must still show
      // which essentials remain so the gamified UI can guide the user.
      final estimate = estimator.estimate(_sample(mass: 0.70, flex: 0, freq: 0));
      expect(estimate.isAvailable, isFalse);
      expect(estimate.essentialsComplete, isFalse);
      final tapTone = estimate.signals
          .firstWhere((signal) => signal.kind == AreSignalKind.tapTone);
      final size = estimate.signals
          .firstWhere((signal) => signal.kind == AreSignalKind.size);
      final weight = estimate.signals
          .firstWhere((signal) => signal.kind == AreSignalKind.weight);
      expect(tapTone.present, isFalse);
      expect(size.present, isTrue);
      expect(weight.present, isTrue);
    });
  });
}
