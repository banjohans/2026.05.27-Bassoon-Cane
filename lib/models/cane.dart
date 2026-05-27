import 'dart:math' as math;

class CaneSample {
  CaneSample({
    required this.id,
    required this.createdAt,
    required this.sampleName,
    required this.purchaseDate,
    required this.source,
    required this.lengthMm,
    required this.widthMm,
    required this.thicknessMm,
    this.thicknessReadingsMm = const [],
    this.innerGougeType = 'none',
    required this.massG,
    required this.flexibilityDeg,
    required this.loadG,
    required this.naturalFrequencyHz,
    this.submergedLengthMm,
    this.density,
    this.hardness,
    this.notes = '',
    this.photoPaths = const [],
    this.resonanceTakesHz = const [],
  });

  final String id;
  final DateTime createdAt;
  final String sampleName;
  final DateTime purchaseDate;
  final String source;
  final double lengthMm;
  final double widthMm;
  final double thicknessMm;
  final List<double> thicknessReadingsMm;
  final String innerGougeType;
  final double massG;
  final double flexibilityDeg;
  final double loadG;
  final double naturalFrequencyHz;
  final double? submergedLengthMm;
  final double? density;
  final double? hardness;
  final String notes;
  final List<String> photoPaths;
  final List<double> resonanceTakesHz;

  CaneSample copyWith({
    String? sampleName,
    DateTime? purchaseDate,
    String? source,
    double? lengthMm,
    double? widthMm,
    double? thicknessMm,
    List<double>? thicknessReadingsMm,
    String? innerGougeType,
    double? massG,
    double? flexibilityDeg,
    double? loadG,
    double? naturalFrequencyHz,
    double? submergedLengthMm,
    double? density,
    double? hardness,
    String? notes,
    List<String>? photoPaths,
    List<double>? resonanceTakesHz,
  }) {
    return CaneSample(
      id: id,
      createdAt: createdAt,
      sampleName: sampleName ?? this.sampleName,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      source: source ?? this.source,
      lengthMm: lengthMm ?? this.lengthMm,
      widthMm: widthMm ?? this.widthMm,
      thicknessMm: thicknessMm ?? this.thicknessMm,
      thicknessReadingsMm: thicknessReadingsMm ?? this.thicknessReadingsMm,
      innerGougeType: innerGougeType ?? this.innerGougeType,
      massG: massG ?? this.massG,
      flexibilityDeg: flexibilityDeg ?? this.flexibilityDeg,
      loadG: loadG ?? this.loadG,
      naturalFrequencyHz: naturalFrequencyHz ?? this.naturalFrequencyHz,
      submergedLengthMm: submergedLengthMm ?? this.submergedLengthMm,
      density: density ?? this.density,
      hardness: hardness ?? this.hardness,
      notes: notes ?? this.notes,
      photoPaths: photoPaths ?? this.photoPaths,
      resonanceTakesHz: resonanceTakesHz ?? this.resonanceTakesHz,
    );
  }

  double get relativeStiffness {
    if (flexibilityDeg <= 0) {
      return 0;
    }
    return loadG / flexibilityDeg;
  }

  // Baseline normalization that keeps geometric effects explicit.
  double get normalizedStiffness {
    final widthFactor = widthMm <= 0 ? 1 : widthMm / 10;
    final lengthFactor = lengthMm <= 0 ? 1 : lengthMm / 100;
    final thicknessFactor = thicknessMm <= 0 ? 1 : thicknessMm / 3;
    return relativeStiffness * lengthFactor * thicknessFactor / widthFactor;
  }

  // Frequency is scaled against geometry to avoid raw-only comparisons.
  double get normalizedFrequency {
    final lengthFactor = lengthMm <= 0 ? 1 : lengthMm / 100;
    final thicknessFactor = thicknessMm <= 0 ? 1 : thicknessMm / 3;
    return naturalFrequencyHz * lengthFactor * thicknessFactor;
  }

  double get submergedRatio {
    if (submergedLengthMm == null || lengthMm <= 0) {
      return 0;
    }
    return (submergedLengthMm! / lengthMm).clamp(0, 1);
  }

  double get nonSubmergedRatio => 1 - submergedRatio;

  // Lauritzen tone-height score (0-36): G# = 0 (highest), B = 36 (lowest).
  double get eigenfrequencyScore {
    return LauritzenToneScale.indexFromFrequency(naturalFrequencyHz);
  }

  double get continuousEigenfrequencyScore {
    return LauritzenToneScale.continuousIndexFromFrequency(naturalFrequencyHz);
  }

  // Backward-compatible alias used in existing UI.
  double get lauritzenToneIndex {
    return eigenfrequencyScore;
  }

  bool get hasFlexibilityMeasurement => flexibilityDeg > 0;

  double? get ari {
    if (!hasFlexibilityMeasurement || naturalFrequencyHz <= 0) {
      return null;
    }
    return flexibilityDeg - eigenfrequencyScore;
  }

  double? get buoyancyPercent {
    if (submergedLengthMm == null || lengthMm <= 0) {
      return null;
    }
    return submergedRatio * 100;
  }

  String get purchaseDateLabel {
    final date = purchaseDate;
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'sampleName': sampleName,
      'purchaseDate': purchaseDate.toIso8601String(),
      'source': source,
      'lengthMm': lengthMm,
      'widthMm': widthMm,
      'thicknessMm': thicknessMm,
      'thicknessReadingsMm': thicknessReadingsMm,
      'innerGougeType': innerGougeType,
      'massG': massG,
      'flexibilityDeg': flexibilityDeg,
      'loadG': loadG,
      'naturalFrequencyHz': naturalFrequencyHz,
      'submergedLengthMm': submergedLengthMm,
      'density': density,
      'hardness': hardness,
      'notes': notes,
      'photoPaths': photoPaths,
      'resonanceTakesHz': resonanceTakesHz,
    };
  }

  factory CaneSample.fromJson(Map<String, dynamic> json) {
    return CaneSample(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
        sampleName: (json['sampleName'] as String?)?.trim().isNotEmpty == true
          ? (json['sampleName'] as String).trim()
          : (json['id'] as String),
      purchaseDate: DateTime.tryParse(json['purchaseDate'] as String? ?? '') ??
          DateTime.tryParse(json['batch'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String? ?? '',
      lengthMm: (json['lengthMm'] as num?)?.toDouble() ?? 0,
      widthMm: (json['widthMm'] as num?)?.toDouble() ?? 0,
      thicknessMm: (json['thicknessMm'] as num?)?.toDouble() ?? 0,
      thicknessReadingsMm: (json['thicknessReadingsMm'] as List<dynamic>? ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
      innerGougeType: json['innerGougeType'] as String? ?? 'none',
      massG: (json['massG'] as num?)?.toDouble() ?? 0,
      flexibilityDeg: (json['flexibilityDeg'] as num?)?.toDouble() ?? 0,
      loadG: (json['loadG'] as num?)?.toDouble() ?? 0,
      naturalFrequencyHz: (json['naturalFrequencyHz'] as num?)?.toDouble() ?? 0,
      submergedLengthMm: (json['submergedLengthMm'] as num?)?.toDouble(),
      density: (json['density'] as num?)?.toDouble(),
      hardness: (json['hardness'] as num?)?.toDouble(),
      notes: json['notes'] as String? ?? '',
      photoPaths: (json['photoPaths'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      resonanceTakesHz: (json['resonanceTakesHz'] as List<dynamic>? ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
    );
  }
}

class LauritzenToneScale {
  // Lauritzen graph anchors: B = 36, C = 32, ... G# = 0.
  // That is 4 fields per semitone across 9 semitone steps.
  static const double highReferenceHz = 1661.22;
  static const double lowReferenceHz = 987.77;
  static const double maxIndex = 36;
  static const double pointsPerSemitone = 4;

  static double indexFromFrequency(double hz) {
    return continuousIndexFromFrequency(hz).round().clamp(0, maxIndex).toDouble();
  }

  static double continuousIndexFromFrequency(double hz) {
    if (hz <= 0) {
      return 0;
    }

    final semitoneOffsetFromB = 12 * _log2(hz / lowReferenceHz);
    final score = maxIndex - (semitoneOffsetFromB * pointsPerSemitone);
    return score.clamp(0, maxIndex).toDouble();
  }

  static double frequencyFromIndex(double index) {
    final clamped = index.clamp(0, maxIndex).toDouble();
    final semitoneOffsetFromB = (maxIndex - clamped) / pointsPerSemitone;
    return lowReferenceHz * math.pow(2, semitoneOffsetFromB / 12);
  }

  static double _log2(double value) => math.log(value) / math.ln2;
}
