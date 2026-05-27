import '../models/cane.dart';
import '../models/reed.dart';

class PredictionResult {
  const PredictionResult({
    required this.targetCane,
    required this.similarityPercent,
    required this.successfulReferenceCount,
    required this.averageReferenceScore,
    required this.featureDeviations,
    required this.referenceAverages,
    required this.explanation,
  });

  final CaneSample targetCane;
  final double similarityPercent;
  final int successfulReferenceCount;
  final double averageReferenceScore;
  final List<String> featureDeviations;
  final Map<String, double> referenceAverages;
  final String explanation;
}

class PredictionEngine {
  PredictionResult? predict({
    required CaneSample target,
    required List<CaneSample> caneSamples,
    required List<ReedEvaluation> reedEvaluations,
  }) {
    final caneById = {for (final sample in caneSamples) sample.id: sample};
    final successful =
        reedEvaluations.where((evaluation) => evaluation.isSuccessful).toList();

    if (successful.isEmpty) {
      return null;
    }

    final similarities = <double>[];
    final scores = <double>[];
    final successfulCanes = <CaneSample>[];

    for (final evaluation in successful) {
      final referenceCane = caneById[evaluation.caneId];
      if (referenceCane == null) {
        continue;
      }
      similarities.add(_similarity(target, referenceCane));
      scores.add(evaluation.overallScore);
      successfulCanes.add(referenceCane);
    }

    if (similarities.isEmpty) {
      return null;
    }

    similarities.sort((a, b) => b.compareTo(a));
    final topMatches = similarities.take(5).toList();
    final avgSimilarity =
        topMatches.reduce((sum, value) => sum + value) / topMatches.length;
    final avgScore = scores.reduce((sum, value) => sum + value) / scores.length;
    final referenceAverages = _referenceAverages(successfulCanes);

    return PredictionResult(
      targetCane: target,
      similarityPercent: avgSimilarity,
      successfulReferenceCount: similarities.length,
      averageReferenceScore: avgScore,
      featureDeviations: _deviations(target, referenceAverages),
      referenceAverages: referenceAverages,
      explanation:
          'Personal predictability score based on normalized stiffness, resonance, and dimensions compared with your successful reed history.',
    );
  }

  Map<String, double> _referenceAverages(List<CaneSample> samples) {
    if (samples.isEmpty) {
      return const {};
    }
    double avg(double Function(CaneSample sample) pick) {
      return samples.map(pick).reduce((a, b) => a + b) / samples.length;
    }

    double? avgOptional(Iterable<double?> values) {
      final present = values.whereType<double>().toList();
      if (present.isEmpty) {
        return null;
      }
      return present.reduce((a, b) => a + b) / present.length;
    }

    return {
      'normalizedStiffness': avg((sample) => sample.normalizedStiffness),
      'normalizedFrequency': avg((sample) => sample.normalizedFrequency),
      'lauritzenToneIndex': avg((sample) => sample.lauritzenToneIndex),
      'ari': avgOptional(samples.map((sample) => sample.ari)) ?? 0,
      'buoyancyPercent': avgOptional(samples.map((sample) => sample.buoyancyPercent)) ?? 0,
      'flexibilityDeg': avg((sample) => sample.flexibilityDeg),
      'massG': avg((sample) => sample.massG),
      'lengthMm': avg((sample) => sample.lengthMm),
      'widthMm': avg((sample) => sample.widthMm),
      'thicknessMm': avg((sample) => sample.thicknessMm),
      'nonSubmergedRatio': avg((sample) => sample.nonSubmergedRatio),
    };
  }

  List<String> _deviations(CaneSample target, Map<String, double> averages) {
    if (averages.isEmpty) {
      return const [];
    }

    final rows = <_DeviationRow>[
      _DeviationRow('normalized stiffness', target.normalizedStiffness,
          averages['normalizedStiffness'] ?? 0),
      _DeviationRow('normalized frequency', target.normalizedFrequency,
          averages['normalizedFrequency'] ?? 0),
        _DeviationRow('eigenfrequency score', target.eigenfrequencyScore,
          averages['lauritzenToneIndex'] ?? 0),
        _DeviationRow('ARI', target.ari ?? 0, averages['ari'] ?? 0),
        _DeviationRow('buoyancy %', target.buoyancyPercent ?? 0,
          averages['buoyancyPercent'] ?? 0),
      _DeviationRow('flexibility', target.flexibilityDeg,
          averages['flexibilityDeg'] ?? 0),
      _DeviationRow('mass', target.massG, averages['massG'] ?? 0),
      _DeviationRow('length', target.lengthMm, averages['lengthMm'] ?? 0),
      _DeviationRow('width', target.widthMm, averages['widthMm'] ?? 0),
      _DeviationRow(
          'thickness', target.thicknessMm, averages['thicknessMm'] ?? 0),
        _DeviationRow('buoyancy (non-submerged ratio)', target.nonSubmergedRatio,
          averages['nonSubmergedRatio'] ?? 0),
    ];

    rows.sort((a, b) => b.percentDelta.abs().compareTo(a.percentDelta.abs()));
    return rows.take(3).map((row) {
      final direction = row.percentDelta > 0 ? 'higher' : 'lower';
      final magnitude = row.percentDelta.abs();
      if (magnitude < 4) {
        return '${row.label} is very close to your successful average';
      }
      return '${row.label} is ${magnitude.toStringAsFixed(1)}% $direction than your successful average';
    }).toList();
  }

  double _similarity(CaneSample a, CaneSample b) {
    final weightedDistance = _featureDistance(a.normalizedStiffness, b.normalizedStiffness, 0.25) +
        _featureDistance(a.normalizedFrequency, b.normalizedFrequency, 0.25) +
      _featureDistance(a.lauritzenToneIndex, b.lauritzenToneIndex, 0.15) +
        _featureDistance(a.flexibilityDeg, b.flexibilityDeg, 0.1) +
        _featureDistance(a.massG, b.massG, 0.1) +
        _featureDistance(a.lengthMm, b.lengthMm, 0.1) +
        _featureDistance(a.widthMm, b.widthMm, 0.1) +
      _featureDistance(a.thicknessMm, b.thicknessMm, 0.05) +
      _featureDistance(a.nonSubmergedRatio, b.nonSubmergedRatio, 0.05);

    final similarity = (1 - weightedDistance).clamp(0, 1);
    return similarity * 100;
  }

  double _featureDistance(double x, double y, double weight) {
    final denominator = [x.abs(), y.abs(), 1.0].reduce((a, b) => a > b ? a : b);
    final distance = (x - y).abs() / denominator;
    return distance * weight;
  }
}

class _DeviationRow {
  const _DeviationRow(this.label, this.target, this.reference);

  final String label;
  final double target;
  final double reference;

  double get percentDelta {
    final denominator = reference.abs() < 0.0001 ? 1.0 : reference.abs();
    return ((target - reference) / denominator) * 100;
  }
}
