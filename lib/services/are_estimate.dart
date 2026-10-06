import '../models/cane.dart';

/// Supplementary, Flexter-free estimate of the Acceptable Reed Estimate (ARE).
///
/// The real ARE needs a flexibility (twist-under-load) reading from an
/// expensive Flexter machine. This estimator reconstructs that flexibility term
/// from cheap measurements the app already captures — tap-tone, weight and size,
/// with float/hardness as corroborating signals — then grades the result on the
/// exact same ARE scale so the user has nothing new to learn.
///
/// Physics: for a cane strip of known geometry, stiffer material (heavier for
/// its size, higher tap pitch) twists less under a fixed load. The dynamic
/// stiffness of a vibrating beam follows `E proportional to rho*f^2*L^4/t^2`
/// (impulse-excitation method, ASTM E1876), which reduces to
/// `mass*f^2*L^3 / (w*t^3)` once density is written as `mass/(L*w*t)`. We
/// express that relative to a typical piece of gouged bassoon cane so the index
/// is ~1.0 for an average sample, map it to an estimated flexibility in degrees,
/// then subtract the Lauritzen tone index just like the real ARE.

/// Reference values for a typical piece of gouged bassoon cane, used to
/// normalise the stiffness index. Anchored on the app's QA reference set
/// (L120 x W14 x T3 mm, ~0.70 g, ~1210 Hz tap, ~21 deg flex).
class AreEstimateReference {
  static const double lengthMm = 120.0;
  static const double widthMm = 14.0;
  static const double thicknessMm = 3.0;
  static const double massG = 0.70;
  static const double frequencyHz = 1210.0;

  /// Flexibility (degrees) of the reference sample.
  static const double flexibilityDeg = 21.0;

  /// Degrees of flexibility lost per +1.0 of normalised stiffness index.
  /// Fitted against the reference set (stiffer cane twists less).
  static const double flexibilityPerStiffness = 13.5;

  /// Plausible flexibility bounds to keep the estimate sane for odd inputs.
  static const double minFlexibilityDeg = 8.0;
  static const double maxFlexibilityDeg = 40.0;
}

/// How much supporting data backs an [AreEstimate]. More signals -> tighter
/// estimate; this drives the reliability message shown to the user.
enum AreEstimateConfidence { none, low, medium, high }

/// The individual input signals that feed the ARE estimate. The two essentials
/// (tap-tone + size) unlock the simulated estimate; the three boosters raise its
/// confidence; a Flexter flexibility reading unlocks the true, measured ARE.
/// Presented to the user as a tidy, gamified checklist.
enum AreSignalKind { tapTone, size, weight, floatTest, hardness, flexibility }

/// The role a signal plays, which drives its checklist tag and grouping.
enum AreSignalRole {
  /// Must be present before any estimate can be shown.
  essential,

  /// Optional corroborating signal that tightens the simulated estimate.
  booster,

  /// Produces the exact, measured ARE (needs a Flexter machine).
  trueAre,
}

extension AreSignalInfo on AreSignalKind {
  /// Short, tidy label for the checklist row.
  String get label {
    switch (this) {
      case AreSignalKind.tapTone:
        return 'Tap-tone';
      case AreSignalKind.size:
        return 'Size';
      case AreSignalKind.weight:
        return 'Weight';
      case AreSignalKind.floatTest:
        return 'Float test';
      case AreSignalKind.hardness:
        return 'Hardness';
      case AreSignalKind.flexibility:
        return 'Flexibility';
    }
  }

  /// Three-to-five word hint describing the task to complete.
  String get hint {
    switch (this) {
      case AreSignalKind.tapTone:
        return 'Record the tapped pitch';
      case AreSignalKind.size:
        return 'Length, width & thickness';
      case AreSignalKind.weight:
        return 'Dry mass in grams';
      case AreSignalKind.floatTest:
        return 'Submerged length';
      case AreSignalKind.hardness:
        return 'Durometer readings';
      case AreSignalKind.flexibility:
        return 'Twist under load — needs a Flexter';
    }
  }

  AreSignalRole get role {
    switch (this) {
      case AreSignalKind.tapTone:
      case AreSignalKind.size:
        return AreSignalRole.essential;
      case AreSignalKind.weight:
      case AreSignalKind.floatTest:
      case AreSignalKind.hardness:
        return AreSignalRole.booster;
      case AreSignalKind.flexibility:
        return AreSignalRole.trueAre;
    }
  }

  /// Essentials must be present before any estimate can be shown.
  bool get isEssential => role == AreSignalRole.essential;
}

/// Presence state of a single [AreSignalKind] for one cane sample.
class AreSignalStatus {
  const AreSignalStatus({required this.kind, required this.present});

  final AreSignalKind kind;
  final bool present;
}

const List<AreSignalStatus> _kEmptySignals = [
  AreSignalStatus(kind: AreSignalKind.tapTone, present: false),
  AreSignalStatus(kind: AreSignalKind.size, present: false),
  AreSignalStatus(kind: AreSignalKind.weight, present: false),
  AreSignalStatus(kind: AreSignalKind.floatTest, present: false),
  AreSignalStatus(kind: AreSignalKind.hardness, present: false),
  AreSignalStatus(kind: AreSignalKind.flexibility, present: false),
];

extension AreEstimateConfidenceLabel on AreEstimateConfidence {
  String get label {
    switch (this) {
      case AreEstimateConfidence.high:
        return 'High confidence';
      case AreEstimateConfidence.medium:
        return 'Medium confidence';
      case AreEstimateConfidence.low:
        return 'Low confidence';
      case AreEstimateConfidence.none:
        return 'Not enough data';
    }
  }
}

/// Result of estimating ARE without a flexibility reading. When [isAvailable]
/// is false the cane is missing the minimum inputs (tap-tone + size) and no
/// number can be shown.
class AreEstimate {
  const AreEstimate({
    required this.estimatedAre,
    required this.estimatedFlexibilityDeg,
    required this.stiffnessIndex,
    required this.confidence,
    required this.signals,
    required this.signalsUsed,
    required this.signalsMissing,
    required this.whatText,
    required this.howText,
    required this.reliabilityText,
  });

  /// Estimated ARE on the standard scale (lower = stiffer for its pitch).
  final double? estimatedAre;
  final double? estimatedFlexibilityDeg;

  /// Normalised stiffness index (~1.0 = typical cane, higher = stiffer).
  final double? stiffnessIndex;
  final AreEstimateConfidence confidence;

  /// Presence state of every input signal, in display order. Drives the
  /// gamified checklist regardless of whether the estimate is available yet.
  final List<AreSignalStatus> signals;

  final List<String> signalsUsed;
  final List<String> signalsMissing;

  /// One-line plain-language "what this is".
  final String whatText;

  /// One-line plain-language "how it was calculated".
  final String howText;

  /// Short reliability note, scaled to how many signals were available.
  final String reliabilityText;

  bool get isAvailable => estimatedAre != null;

  /// The essential + booster signals that feed the simulated estimate (i.e. all
  /// signals except the Flexter flexibility reading). Drives the strength meter.
  List<AreSignalStatus> get estimateSignals => signals
      .where((signal) => signal.kind.role != AreSignalRole.trueAre)
      .toList();

  /// The Flexter flexibility signal(s) that unlock the true, measured ARE.
  List<AreSignalStatus> get trueAreSignals => signals
      .where((signal) => signal.kind.role == AreSignalRole.trueAre)
      .toList();

  /// How many of the simulated-estimate signals are present. Used for the meter.
  int get signalsPresentCount =>
      estimateSignals.where((signal) => signal.present).length;

  /// Whether both essentials (tap-tone + size) are present, which is what
  /// unlocks any estimate at all.
  bool get essentialsComplete => signals
      .where((signal) => signal.kind.isEssential)
      .every((signal) => signal.present);

  static const AreEstimate unavailable = AreEstimate(
    estimatedAre: null,
    estimatedFlexibilityDeg: null,
    stiffnessIndex: null,
    confidence: AreEstimateConfidence.none,
    signals: _kEmptySignals,
    signalsUsed: [],
    signalsMissing: ['tap-tone', 'size'],
    whatText:
        'A Flexter-free estimate of ARE from weight, size and tap-tone - for '
        'when you have no flexibility reading.',
    howText: 'Add a tap-tone frequency and the cane size to calculate it.',
    reliabilityText:
        'Needs at least a tap-tone and the cane length, width and thickness.',
  );
}

/// Computes the supplementary ARE estimate from a [CaneSample]. Pure Dart and
/// side-effect free so it can be unit-tested against the reference set.
class AreEstimator {
  const AreEstimator();

  AreEstimate estimate(CaneSample sample) {
    final hasGeometry =
        sample.lengthMm > 0 && sample.widthMm > 0 && sample.thicknessMm > 0;
    final hasTapTone = sample.naturalFrequencyHz > 0;
    final hasMass = sample.massG > 0;
    final hasBuoyancy = sample.buoyancyPercent != null;
    final hasHardness = sample.hardness != null && sample.hardness! > 0;
    final hasFlexibility = sample.flexibilityDeg > 0;

    // Presence of every signal, in display order. Computed up front so the
    // checklist stays accurate even when the estimate itself is still locked.
    final signals = <AreSignalStatus>[
      AreSignalStatus(kind: AreSignalKind.tapTone, present: hasTapTone),
      AreSignalStatus(kind: AreSignalKind.size, present: hasGeometry),
      AreSignalStatus(kind: AreSignalKind.weight, present: hasMass),
      AreSignalStatus(kind: AreSignalKind.floatTest, present: hasBuoyancy),
      AreSignalStatus(kind: AreSignalKind.hardness, present: hasHardness),
      AreSignalStatus(kind: AreSignalKind.flexibility, present: hasFlexibility),
    ];

    // Minimum viable inputs: a tap-tone and the cane dimensions.
    if (!hasGeometry || !hasTapTone) {
      return AreEstimate(
        estimatedAre: null,
        estimatedFlexibilityDeg: null,
        stiffnessIndex: null,
        confidence: AreEstimateConfidence.none,
        signals: signals,
        signalsUsed: [
          for (final signal in signals)
            if (signal.present) signal.kind.label.toLowerCase(),
        ],
        signalsMissing: [
          for (final kind in [AreSignalKind.tapTone, AreSignalKind.size])
            if (!signals.firstWhere((s) => s.kind == kind).present)
              kind.label.toLowerCase(),
        ],
        whatText: AreEstimate.unavailable.whatText,
        howText:
            'Add the tapped pitch and the cane length, width and thickness to '
            'unlock the estimate.',
        reliabilityText: AreEstimate.unavailable.reliabilityText,
      );
    }

    // Density ratio from weight; fall back to the reference piece when weight
    // is missing (we then only have resonance + geometry, so confidence drops).
    final massRatio =
        hasMass ? sample.massG / AreEstimateReference.massG : 1.0;
    final freqRatio =
        sample.naturalFrequencyHz / AreEstimateReference.frequencyHz;
    final lengthRatio = sample.lengthMm / AreEstimateReference.lengthMm;
    final widthRatio = AreEstimateReference.widthMm / sample.widthMm;
    final thicknessRatio =
        AreEstimateReference.thicknessMm / sample.thicknessMm;

    // E proportional to mass*f^2*L^3 / (w*t^3), normalised so a typical piece ~ 1.0.
    final stiffnessIndex = massRatio *
        (freqRatio * freqRatio) *
        (lengthRatio * lengthRatio * lengthRatio) *
        widthRatio *
        (thicknessRatio * thicknessRatio * thicknessRatio);

    // Stiffer cane twists less: map the index to an estimated flexibility.
    final rawFlex = AreEstimateReference.flexibilityDeg -
        AreEstimateReference.flexibilityPerStiffness * (stiffnessIndex - 1.0);
    final estFlex = rawFlex.clamp(
      AreEstimateReference.minFlexibilityDeg,
      AreEstimateReference.maxFlexibilityDeg,
    );

    // Same final step as the real ARE: flexibility - Lauritzen tone index.
    final estimatedAre = estFlex - sample.eigenfrequencyScore;

    final used = <String>['tap-tone', 'size'];
    final missing = <String>[];
    if (hasMass) {
      used.add('weight');
    } else {
      missing.add('weight');
    }
    if (hasBuoyancy) {
      used.add('float test');
    } else {
      missing.add('float test');
    }
    if (hasHardness) {
      used.add('hardness');
    } else {
      missing.add('hardness');
    }

    final confidence = _confidenceFor(
      hasMass: hasMass,
      corroborating: (hasBuoyancy ? 1 : 0) + (hasHardness ? 1 : 0),
    );

    return AreEstimate(
      estimatedAre: estimatedAre,
      estimatedFlexibilityDeg: estFlex.toDouble(),
      stiffnessIndex: stiffnessIndex,
      confidence: confidence,
      signals: signals,
      signalsUsed: used,
      signalsMissing: missing,
      whatText:
          'Estimates the Flexter flexibility from this cane\'s weight, size and '
          'tap-tone, then grades it on the normal ARE scale.',
      howText:
          'Heavier cane with a higher tap pitch for its size is stiffer, so it '
          'twists less - we predict that flexibility, then subtract the tone '
          'index like a normal ARE.',
      reliabilityText: _reliabilityText(confidence, used.length, missing),
    );
  }

  AreEstimateConfidence _confidenceFor({
    required bool hasMass,
    required int corroborating,
  }) {
    if (hasMass && corroborating >= 1) {
      return AreEstimateConfidence.high;
    }
    if (hasMass || corroborating >= 1) {
      return AreEstimateConfidence.medium;
    }
    // Resonance + geometry only - weakest supported case.
    return AreEstimateConfidence.low;
  }

  String _reliabilityText(
    AreEstimateConfidence confidence,
    int usedCount,
    List<String> missing,
  ) {
    const total = 5; // tap-tone, size, weight, float test, hardness
    const base =
        'This is an approximation of a Flexter reading - a screening hint, '
        'not a verdict.';
    final coverage = 'Based on $usedCount of $total signals.';
    if (confidence == AreEstimateConfidence.high || missing.isEmpty) {
      return '$coverage $base';
    }
    return '$coverage Add ${_joinSignals(missing)} to tighten it. $base';
  }

  String _joinSignals(List<String> signals) {
    if (signals.length == 1) {
      return signals.first;
    }
    final head = signals.sublist(0, signals.length - 1).join(', ');
    return '$head or ${signals.last}';
  }
}
