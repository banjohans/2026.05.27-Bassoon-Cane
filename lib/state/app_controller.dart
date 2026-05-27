import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/cane.dart';
import '../models/reed.dart';
import '../services/local_store.dart';
import '../services/prediction_engine.dart';

class AppController extends ChangeNotifier {
  AppController({
    LocalStore? localStore,
    SyncGateway? syncGateway,
    PredictionEngine? predictionEngine,
  })  : _localStore = localStore ?? LocalStore(),
        _syncGateway = syncGateway ?? SyncGateway(),
        _predictionEngine = predictionEngine ?? PredictionEngine();

  final LocalStore _localStore;
  final SyncGateway _syncGateway;
  final PredictionEngine _predictionEngine;
  final Uuid _uuid = const Uuid();

  bool _isLoading = true;
  String? _errorMessage;
  List<CaneSample> _caneSamples = [];
  List<ReedEvaluation> _reedEvaluations = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<CaneSample> get caneSamples => List.unmodifiable(_caneSamples);
  List<ReedEvaluation> get reedEvaluations => List.unmodifiable(_reedEvaluations);
  List<String> get sourceHistory {
    final sources = _caneSamples
        .map((sample) => sample.source.trim())
        .where((source) => source.isNotEmpty)
        .toSet()
        .toList();
    sources.sort();
    return sources;
  }

  List<double> get thicknessOuterHistory {
    return _sortedDistinct(
      _caneSamples.map((sample) => sample.thicknessMm),
    );
  }

  List<double> get lengthHistory {
    return _sortedDistinct(
      _caneSamples.map((sample) => sample.lengthMm),
    );
  }

  List<double> get widthHistory {
    return _sortedDistinct(
      _caneSamples.map((sample) => sample.widthMm),
    );
  }

  List<double> get thicknessMiddleHistory {
    return _sortedDistinct(
      _caneSamples
          .where((sample) => sample.thicknessReadingsMm.length > 1)
          .map((sample) => sample.thicknessReadingsMm[1]),
    );
  }

  List<double> get thicknessBackHistory {
    return _sortedDistinct(
      _caneSamples
          .where((sample) => sample.thicknessReadingsMm.length > 2)
          .map((sample) => sample.thicknessReadingsMm[2]),
    );
  }

  List<double> get massHistory {
    return _sortedDistinct(
      _caneSamples
          .map((sample) => sample.massG)
          .where((value) => value > 0),
    );
  }

  List<double> get flexibilityHistory {
    return _sortedDistinct(
      _caneSamples
          .map((sample) => sample.flexibilityDeg)
          .where((value) => value > 0),
    );
  }

  List<double> get loadHistory {
    return _sortedDistinct(
      _caneSamples
          .map((sample) => sample.loadG)
          .where((value) => value > 0),
    );
  }

  List<double> get frequencyHistory {
    return _sortedDistinct(
      _caneSamples
          .map((sample) => sample.naturalFrequencyHz)
          .where((value) => value > 0),
    );
  }

  List<double> get submergedLengthHistory {
    return _sortedDistinct(
      _caneSamples
          .map((sample) => sample.submergedLengthMm)
          .whereType<double>()
          .where((value) => value > 0),
    );
  }

  List<double> get hardnessHistory {
    return _sortedDistinct(
      _caneSamples
          .map((sample) => sample.hardness)
          .whereType<double>()
          .where((value) => value > 0),
    );
  }

  double? get averageMassG {
    final values = _caneSamples.map((sample) => sample.massG).where((value) => value > 0).toList();
    if (values.isEmpty) {
      return null;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  double? get averageFlexibilityDeg {
    final values = _caneSamples
        .map((sample) => sample.flexibilityDeg)
        .where((value) => value > 0)
        .toList();
    if (values.isEmpty) {
      return null;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  String exportDatabaseJson({bool pretty = true}) {
    final payload = {
      'caneSamples': _caneSamples.map((sample) => sample.toJson()).toList(),
      'reedEvaluations': _reedEvaluations
          .map((evaluation) => evaluation.toJson())
          .toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(payload);
    }
    return jsonEncode(payload);
  }

  Future<({int caneCount, int reedCount})> importDatabaseJson(
    String jsonString, {
    bool merge = false,
  }) async {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid JSON format. Expected an object.');
    }

    final caneRaw =
        (decoded['caneSamples'] ?? decoded['canes'] ?? const <dynamic>[])
            as List<dynamic>;
    final reedRaw =
        (decoded['reedEvaluations'] ?? decoded['reeds'] ?? const <dynamic>[])
            as List<dynamic>;

    final importedCanes = caneRaw
        .map((item) => CaneSample.fromJson(item as Map<String, dynamic>))
        .toList();
    final importedReeds = reedRaw
        .map((item) => ReedEvaluation.fromJson(item as Map<String, dynamic>))
        .toList();

    if (merge) {
      final caneById = {for (final sample in _caneSamples) sample.id: sample};
      for (final sample in importedCanes) {
        caneById[sample.id] = sample;
      }
      _caneSamples = caneById.values.toList();

      final validCaneIds = _caneSamples.map((sample) => sample.id).toSet();
      final reedById = {
        for (final evaluation in _reedEvaluations)
          if (validCaneIds.contains(evaluation.caneId)) evaluation.id: evaluation,
      };
      for (final evaluation in importedReeds) {
        if (!validCaneIds.contains(evaluation.caneId)) {
          continue;
        }
        reedById[evaluation.id] = evaluation;
      }
      _reedEvaluations = reedById.values.toList();
    } else {
      final validCaneIds = importedCanes.map((sample) => sample.id).toSet();
      _caneSamples = importedCanes;
      _reedEvaluations = importedReeds
          .where((evaluation) => validCaneIds.contains(evaluation.caneId))
          .toList();
    }

    await _persist();
    notifyListeners();
    return (caneCount: _caneSamples.length, reedCount: _reedEvaluations.length);
  }

  Future<void> initialize() async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _localStore.load();
      _caneSamples = snapshot.caneSamples;
      _reedEvaluations = snapshot.reedEvaluations;
      await _ensureGraph4QaSeed();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to load local data: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addCaneSample({
    required String sampleName,
    required DateTime purchaseDate,
    required String source,
    required double lengthMm,
    required double widthMm,
    required double thicknessMm,
    required List<double> thicknessReadingsMm,
    required String innerGougeType,
    required double massG,
    required double flexibilityDeg,
    required double loadG,
    required double naturalFrequencyHz,
    double? submergedLengthMm,
    double? density,
    double? hardness,
    String notes = '',
    List<String> photoPaths = const [],
    List<double> resonanceTakesHz = const [],
  }) async {
    final sample = CaneSample(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      sampleName: sampleName,
      purchaseDate: purchaseDate,
      source: source,
      lengthMm: lengthMm,
      widthMm: widthMm,
      thicknessMm: thicknessMm,
      thicknessReadingsMm: thicknessReadingsMm,
      innerGougeType: innerGougeType,
      massG: massG,
      flexibilityDeg: flexibilityDeg,
      loadG: loadG,
      naturalFrequencyHz: naturalFrequencyHz,
      submergedLengthMm: submergedLengthMm,
      density: density,
      hardness: hardness,
      notes: notes,
      photoPaths: photoPaths,
      resonanceTakesHz: resonanceTakesHz,
    );

    _caneSamples = [..._caneSamples, sample];
    await _persist();
    notifyListeners();
  }

  Future<void> updateCaneSample({
    required String id,
    required String sampleName,
    required DateTime purchaseDate,
    required String source,
    required double lengthMm,
    required double widthMm,
    required double thicknessMm,
    required List<double> thicknessReadingsMm,
    required String innerGougeType,
    required double massG,
    required double flexibilityDeg,
    required double loadG,
    required double naturalFrequencyHz,
    double? submergedLengthMm,
    double? density,
    double? hardness,
    String notes = '',
    List<String> photoPaths = const [],
    List<double> resonanceTakesHz = const [],
  }) async {
    _caneSamples = _caneSamples.map((sample) {
      if (sample.id != id) {
        return sample;
      }
      return sample.copyWith(
        sampleName: sampleName,
        purchaseDate: purchaseDate,
        source: source,
        lengthMm: lengthMm,
        widthMm: widthMm,
        thicknessMm: thicknessMm,
        thicknessReadingsMm: thicknessReadingsMm,
        innerGougeType: innerGougeType,
        massG: massG,
        flexibilityDeg: flexibilityDeg,
        loadG: loadG,
        naturalFrequencyHz: naturalFrequencyHz,
        submergedLengthMm: submergedLengthMm,
        density: density,
        hardness: hardness,
        notes: notes,
        photoPaths: photoPaths,
        resonanceTakesHz: resonanceTakesHz,
      );
    }).toList();

    await _persist();
    notifyListeners();
  }

  Future<void> deleteCaneSample(String id) async {
    _caneSamples = _caneSamples.where((sample) => sample.id != id).toList();
    _reedEvaluations =
        _reedEvaluations.where((evaluation) => evaluation.caneId != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> addReedEvaluation({
    required String caneId,
    required int response,
    required int stability,
    required int tone,
    required int intonation,
    required int flexibility,
    required int projection,
    required int resistance,
    String comment = '',
    bool goldStandard = false,
    int? longevityDays,
    List<String> photoPaths = const [],
  }) async {
    final evaluation = ReedEvaluation(
      id: _uuid.v4(),
      caneId: caneId,
      createdAt: DateTime.now(),
      response: response,
      stability: stability,
      tone: tone,
      intonation: intonation,
      flexibility: flexibility,
      projection: projection,
      resistance: resistance,
      comment: comment,
      goldStandard: goldStandard,
      longevityDays: longevityDays,
      photoPaths: photoPaths,
    );

    _reedEvaluations = [..._reedEvaluations, evaluation];
    await _persist();
    notifyListeners();
  }

  Future<void> updateReedEvaluation({
    required String id,
    required String caneId,
    required int response,
    required int stability,
    required int tone,
    required int intonation,
    required int flexibility,
    required int projection,
    required int resistance,
    String comment = '',
    bool goldStandard = false,
    int? longevityDays,
    List<String> photoPaths = const [],
  }) async {
    _reedEvaluations = _reedEvaluations.map((evaluation) {
      if (evaluation.id != id) {
        return evaluation;
      }
      return evaluation.copyWith(
        caneId: caneId,
        response: response,
        stability: stability,
        tone: tone,
        intonation: intonation,
        flexibility: flexibility,
        projection: projection,
        resistance: resistance,
        comment: comment,
        goldStandard: goldStandard,
        longevityDays: longevityDays,
        photoPaths: photoPaths,
      );
    }).toList();

    await _persist();
    notifyListeners();
  }

  Future<void> deleteReedEvaluation(String id) async {
    _reedEvaluations =
        _reedEvaluations.where((evaluation) => evaluation.id != id).toList();
    await _persist();
    notifyListeners();
  }

  CaneSample? findCane(String id) {
    for (final sample in _caneSamples) {
      if (sample.id == id) {
        return sample;
      }
    }
    return null;
  }

  ReedEvaluation? findReedEvaluation(String id) {
    for (final evaluation in _reedEvaluations) {
      if (evaluation.id == id) {
        return evaluation;
      }
    }
    return null;
  }

  PredictionResult? predictForCane(String caneId) {
    final sample = findCane(caneId);
    if (sample == null) {
      return null;
    }

    return _predictionEngine.predict(
      target: sample,
      caneSamples: _caneSamples,
      reedEvaluations: _reedEvaluations,
    );
  }

  PredictionResult? predictForDraft({
    required DateTime purchaseDate,
    required double lengthMm,
    required double widthMm,
    required double thicknessMm,
    required double massG,
    required double flexibilityDeg,
    required double loadG,
    required double naturalFrequencyHz,
    required List<double> thicknessReadingsMm,
    required String innerGougeType,
    double? submergedLengthMm,
  }) {
    final draft = CaneSample(
      id: 'draft',
      createdAt: DateTime.now(),
      sampleName: 'Live draft',
      purchaseDate: purchaseDate,
      source: 'Live input',
      lengthMm: lengthMm,
      widthMm: widthMm,
      thicknessMm: thicknessMm,
      thicknessReadingsMm: thicknessReadingsMm,
      innerGougeType: innerGougeType,
      massG: massG,
      flexibilityDeg: flexibilityDeg,
      loadG: loadG,
      naturalFrequencyHz: naturalFrequencyHz,
      submergedLengthMm: submergedLengthMm,
    );

    return _predictionEngine.predict(
      target: draft,
      caneSamples: _caneSamples,
      reedEvaluations: _reedEvaluations,
    );
  }

  int get successfulReedCount =>
      _reedEvaluations.where((evaluation) => evaluation.isSuccessful).length;

  Future<void> _persist() async {
    try {
      await _localStore.save(
        caneSamples: _caneSamples,
        reedEvaluations: _reedEvaluations,
      );
      await _syncGateway.syncNow(
        caneSamples: _caneSamples,
        reedEvaluations: _reedEvaluations,
      );
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to save data: $error';
    }
  }

  Future<void> _ensureGraph4QaSeed() async {
    if (kIsWeb) {
      await _upsertGraph4CanonicalSubset();
      return;
    }

    final alreadySeeded = _caneSamples.any((sample) => sample.sampleName.startsWith('G4-'));
    if (alreadySeeded) {
      await _upsertGraph4CanonicalSubset();
      return;
    }

    final seededCanes = <CaneSample>[];
    final seededReeds = <ReedEvaluation>[];
    final baseDate = DateTime(2024, 1, 1);

    for (int i = 0; i < _graph4Rows.length; i++) {
      final row = _graph4Rows[i];
      final caneId = _uuid.v4();
      final createdAt = baseDate.add(Duration(days: i));
      final hardnessAvg = (row.hardnessA + row.hardnessB) / 2;

      final cane = CaneSample(
        id: caneId,
        createdAt: createdAt,
        sampleName: 'G4-${row.name}',
        purchaseDate: createdAt,
        source: row.supplier ?? 'Graph4-Are Preliminary',
        lengthMm: 120,
        widthMm: 14,
        thicknessMm: 3,
        thicknessReadingsMm: const [3, 3, 3],
        innerGougeType: 'none',
        massG: 0,
        flexibilityDeg: row.flex,
        loadG: 200,
        naturalFrequencyHz: LauritzenToneScale.frequencyFromIndex(row.toneScore),
        hardness: hardnessAvg,
        notes:
          'Imported from Graph 4 | Batch: ${row.batch ?? 'n/a'} | Tone: ${row.toneLabel ?? 'n/a'} (${row.toneScore.toStringAsFixed(0)}) | ARI: ${row.ari?.toStringAsFixed(1) ?? 'n/a'} | Grade: ${_internationalGradeFromGraphTag(row.ratingTag) ?? 'no explicit grade'}',
      );
      seededCanes.add(cane);

      final score = _scoreFromGraphTag(row.ratingTag);
      if (score == null) {
        continue;
      }

      final reed = ReedEvaluation(
        id: _uuid.v4(),
        caneId: caneId,
        createdAt: createdAt.add(const Duration(hours: 8)),
        response: score,
        stability: score,
        tone: score,
        intonation: score,
        flexibility: score,
        projection: score,
        resistance: score,
        comment:
            'Graph 4 grade: ${_internationalGradeFromGraphTag(row.ratingTag) ?? 'n/a'}',
      );
      seededReeds.add(reed);
    }

    _caneSamples = [..._caneSamples, ...seededCanes];
    _reedEvaluations = [..._reedEvaluations, ...seededReeds];
    await _persist();
  }

  Future<void> _upsertGraph4CanonicalSubset() async {
    final canonicalRows = _graph4Rows
        .where((row) => _scoreFromGraphTag(row.ratingTag) != null)
        .take(20)
        .toList();
    final canonicalNames = canonicalRows
        .map((row) => 'G4-${row.name}')
        .toSet();

    final canonicalCaneIds = _caneSamples
        .where((sample) => canonicalNames.contains(sample.sampleName))
        .map((sample) => sample.id)
        .toSet();

    _reedEvaluations = _reedEvaluations
        .where((evaluation) => !canonicalCaneIds.contains(evaluation.caneId))
        .toList();
    _caneSamples = _caneSamples
        .where((sample) => !canonicalNames.contains(sample.sampleName))
        .toList();

    final seededCanes = <CaneSample>[];
    final seededReeds = <ReedEvaluation>[];
    final baseDate = DateTime(2024, 1, 1);

    for (int i = 0; i < canonicalRows.length; i++) {
      final row = canonicalRows[i];
      final caneId = _uuid.v4();
      final createdAt = baseDate.add(Duration(days: i));
      final hardnessAvg = (row.hardnessA + row.hardnessB) / 2;

      final cane = CaneSample(
        id: caneId,
        createdAt: createdAt,
        sampleName: 'G4-${row.name}',
        purchaseDate: createdAt,
        source: row.supplier ?? 'Graph4-Are Preliminary',
        lengthMm: 120,
        widthMm: 14,
        thicknessMm: 3,
        thicknessReadingsMm: const [3, 3, 3],
        innerGougeType: 'none',
        massG: 0,
        flexibilityDeg: row.flex,
        loadG: 200,
        naturalFrequencyHz: LauritzenToneScale.frequencyFromIndex(row.toneScore),
        hardness: hardnessAvg,
        notes:
          'Imported from Graph 4 | Batch: ${row.batch ?? 'n/a'} | Tone: ${row.toneLabel ?? 'n/a'} (${row.toneScore.toStringAsFixed(0)}) | ARI: ${row.ari?.toStringAsFixed(1) ?? 'n/a'} | Grade: ${_internationalGradeFromGraphTag(row.ratingTag) ?? 'no explicit grade'}',
      );
      seededCanes.add(cane);

      final score = _scoreFromGraphTag(row.ratingTag);
      if (score == null) {
        continue;
      }

      seededReeds.add(
        ReedEvaluation(
          id: _uuid.v4(),
          caneId: caneId,
          createdAt: createdAt.add(const Duration(hours: 8)),
          response: score,
          stability: score,
          tone: score,
          intonation: score,
          flexibility: score,
          projection: score,
          resistance: score,
          comment:
              'Graph 4 grade: ${_internationalGradeFromGraphTag(row.ratingTag) ?? 'n/a'}',
        ),
      );
    }

    _caneSamples = [..._caneSamples, ...seededCanes];
    _reedEvaluations = [..._reedEvaluations, ...seededReeds];
    await _persist();
  }

  int? _scoreFromGraphTag(String? tag) {
    if (tag == null) {
      return null;
    }
    final normalized = tag.trim().toUpperCase();
    switch (normalized) {
      case 'A+':
        return 10;
      case 'A':
        return 9;
      case 'A-':
        return 8;
      case 'B+':
        return 7;
      case 'B':
        return 6;
      case 'B-':
        return 5;
      case 'C+':
        return 4;
      case 'C':
        return 3;
      case 'C-':
        return 2;
      case 'D':
        return 1;
      case 'M+':
        return 10;
      case 'M':
        return 9;
      case 'M-':
        return 8;
      case 'S+':
        return 7;
      case 'S/M':
        return 6;
      case '(G)M':
      case 'G':
        return 8;
      case '(M)M+':
        return 9;
      case 'NG+':
        return 4;
      case 'NG':
        return 3;
      case 'SPRAKK':
      case 'SPRAKK?':
        return 5;
      default:
        return null;
    }
  }

  String? _internationalGradeFromGraphTag(String? tag) {
    final score = _scoreFromGraphTag(tag);
    if (score == null) {
      return null;
    }
    return ReedEvaluation.gradeForScore(score.toDouble());
  }

  List<double> _sortedDistinct(Iterable<double> values) {
    final rounded = values
        .where((value) => value > 0)
        .map((value) => double.parse(value.toStringAsFixed(3)))
        .toSet()
        .toList();
    rounded.sort();
    return rounded.reversed.toList();
  }
}

class _Graph4Row {
  const _Graph4Row({
    required this.name,
    required this.flex,
    this.toneLabel,
    required this.toneScore,
    this.ari,
    required this.hardnessA,
    required this.hardnessB,
    this.batch,
    this.supplier,
    this.ratingTag,
  });

  final String name;
  final double flex;
  final String? toneLabel;
  final double toneScore;
  final double? ari;
  final int hardnessA;
  final int hardnessB;
  final String? batch;
  final String? supplier;
  final String? ratingTag;
}

const List<_Graph4Row> _graph4Rows = [
  _Graph4Row(name: 'A', batch: 'Rigotti2', supplier: 'Bonazza', flex: 20, toneLabel: 'E+', toneScore: 15, ari: 5.0, hardnessA: 13, hardnessB: 15),
  _Graph4Row(name: 'B', batch: 'Rigotti2', supplier: 'Bonazza', flex: 21, toneLabel: 'D++', toneScore: 22, ari: -1.0, hardnessA: 13, hardnessB: 14),
  _Graph4Row(name: 'C', batch: 'Rigotti2', supplier: 'Bonazza', flex: 23, toneLabel: 'F++', toneScore: 10, ari: 13.0, hardnessA: 15, hardnessB: 16),
  _Graph4Row(name: 'D', batch: 'Rigotti2', supplier: 'Bonazza', flex: 20, toneLabel: 'E-', toneScore: 17, ari: 3.0, hardnessA: 11, hardnessB: 15),
  _Graph4Row(name: 'E', batch: 'Rigotti2', supplier: 'Bonazza', flex: 19, toneLabel: 'F+', toneScore: 13, ari: 6.0, hardnessA: 13, hardnessB: 13),
  _Graph4Row(name: 'F', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22, toneLabel: 'F', toneScore: 11, ari: 11.0, hardnessA: 13, hardnessB: 14),
  _Graph4Row(name: 'G', batch: 'Rigotti2', supplier: 'Bonazza', flex: 18, toneLabel: 'G#+', toneScore: 26, ari: -8.0, hardnessA: 15, hardnessB: 16),
  _Graph4Row(name: 'H', batch: 'Rigotti2', supplier: 'Bonazza', flex: 20, toneLabel: 'E+', toneScore: 15, ari: 5.0, hardnessA: 13, hardnessB: 13),
  _Graph4Row(name: 'I', batch: 'Rigotti2', supplier: 'Bonazza', flex: 18, toneLabel: 'D-', toneScore: 25, ari: -7.0, hardnessA: 10, hardnessB: 13),
  _Graph4Row(name: 'J', batch: 'Rigotti2', supplier: 'Bonazza', flex: 20, toneLabel: 'D', toneScore: 16, ari: 4.0, hardnessA: 14, hardnessB: 14),
  _Graph4Row(name: 'K', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22, toneLabel: 'G#+', toneScore: 29, ari: -7.0, hardnessA: 12, hardnessB: 14),
  _Graph4Row(name: 'L', batch: 'Rigotti2', supplier: 'Bonazza', flex: 20, toneLabel: 'F', toneScore: 12, ari: 8.0, hardnessA: 15, hardnessB: 16),
  _Graph4Row(name: 'M', batch: 'Rigotti2', supplier: 'Bonazza', flex: 20, toneLabel: 'F', toneScore: 12, ari: 8.0, hardnessA: 12, hardnessB: 14),
  _Graph4Row(name: 'N', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22, toneLabel: 'D++', toneScore: 18, ari: 4.0, hardnessA: 11, hardnessB: 13),
  _Graph4Row(name: 'O', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22, toneLabel: 'F', toneScore: 12, ari: 10.0, hardnessA: 12, hardnessB: 14),
  _Graph4Row(name: 'P', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22, toneLabel: 'D', toneScore: 24, ari: -2.0, hardnessA: 14, hardnessB: 15),
  _Graph4Row(name: 'Q', batch: 'Rigotti2', supplier: 'Bonazza', flex: 21, toneLabel: 'F-', toneScore: 13, ari: 8.0, hardnessA: 13, hardnessB: 15),
  _Graph4Row(name: 'R', batch: 'Rigotti2', supplier: 'Bonazza', flex: 18, toneLabel: 'F', toneScore: 12, ari: 6.0, hardnessA: 14, hardnessB: 13),
  _Graph4Row(name: 'S', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22, toneLabel: 'F', toneScore: 12, ari: 10.0, hardnessA: 15, hardnessB: 16),
  _Graph4Row(name: 'T', batch: 'Rigotti2', supplier: 'Bonazza', flex: 22.5, toneLabel: 'D-', toneScore: 25, ari: -2.5, hardnessA: 14, hardnessB: 15),
  _Graph4Row(name: 'U', flex: 23.0, toneScore: 18, hardnessA: 13, hardnessB: 14),
  _Graph4Row(name: 'V', flex: 20.3, toneScore: 25, hardnessA: 9, hardnessB: 11, ratingTag: 'M'),
  _Graph4Row(name: 'W', flex: 19.6, toneScore: 11, hardnessA: 10, hardnessB: 11),
  _Graph4Row(name: 'X', flex: 18.2, toneScore: 14, hardnessA: 12, hardnessB: 12),
  _Graph4Row(name: 'Y', flex: 21.5, toneScore: 22, hardnessA: 13, hardnessB: 15),
  _Graph4Row(name: 'Z', flex: 21.5, toneScore: 20, hardnessA: 13, hardnessB: 15),
  _Graph4Row(name: 'AA', flex: 23.8, toneScore: 24, hardnessA: 14, hardnessB: 14, ratingTag: 'M'),
  _Graph4Row(name: 'AB', flex: 23.0, toneScore: 1, hardnessA: 12, hardnessB: 15, ratingTag: 'NG'),
  _Graph4Row(name: 'AC', flex: 21.5, toneScore: 17, hardnessA: 10, hardnessB: 11, ratingTag: 'M'),
  _Graph4Row(name: 'AD', flex: 20.0, toneScore: 12, hardnessA: 13, hardnessB: 15, ratingTag: 'NG'),
  _Graph4Row(name: 'AE', flex: 20.8, toneScore: 14, hardnessA: 12, hardnessB: 16),
  _Graph4Row(name: 'AF', flex: 19.3, toneScore: 9, hardnessA: 11, hardnessB: 12, ratingTag: 'NG'),
  _Graph4Row(name: 'AG', flex: 22.3, toneScore: 22, hardnessA: 15, hardnessB: 15, ratingTag: 'M'),
  _Graph4Row(name: 'AH', flex: 14.9, toneScore: 18, hardnessA: 15, hardnessB: 15, ratingTag: 'SPRAKK?'),
  _Graph4Row(name: 'AI', flex: 10.4, toneScore: 17, hardnessA: 14, hardnessB: 12, ratingTag: '(G)M'),
  _Graph4Row(name: 'AJ', flex: 15.4, toneScore: 20, hardnessA: 16, hardnessB: 14, ratingTag: '(M)M+'),
  _Graph4Row(name: 'AK', flex: 13.8, toneScore: 22, hardnessA: 14, hardnessB: 13, ratingTag: 'M+'),
  _Graph4Row(name: 'AL', flex: 18.5, toneScore: 16, hardnessA: 13, hardnessB: 13, ratingTag: 'M-'),
  _Graph4Row(name: 'AM', flex: 13.3, toneScore: 17, hardnessA: 13, hardnessB: 16, ratingTag: 'M'),
  _Graph4Row(name: 'AN', flex: 25.1, toneScore: 24, hardnessA: 25, hardnessB: 25, ratingTag: 'S+'),
  _Graph4Row(name: 'AO', flex: 11.8, toneScore: 14, hardnessA: 15, hardnessB: 17, ratingTag: 'M'),
  _Graph4Row(name: 'AP', flex: 24.3, toneScore: 32, hardnessA: 13, hardnessB: 15, ratingTag: 'M+'),
  _Graph4Row(name: 'AQ', flex: 23.6, toneScore: 25, hardnessA: 13, hardnessB: 15, ratingTag: 'NG+'),
  _Graph4Row(name: 'AR', flex: 25.6, toneScore: 25, hardnessA: 11, hardnessB: 13, ratingTag: 'S/M'),
  _Graph4Row(name: 'AS', flex: 24.2, toneScore: 25, hardnessA: 13, hardnessB: 16, ratingTag: 'M+'),
  _Graph4Row(name: 'AT', flex: 26.6, toneScore: 27, hardnessA: 15, hardnessB: 16, ratingTag: 'S/M'),
  _Graph4Row(name: 'AU', flex: 25.8, toneScore: 25, hardnessA: 14, hardnessB: 14, ratingTag: 'S/M'),
  _Graph4Row(name: 'AV', flex: 22.8, toneScore: 24, hardnessA: 14, hardnessB: 17, ratingTag: 'S/M'),
  _Graph4Row(name: 'AW', flex: 23.5, toneScore: 24, hardnessA: 14, hardnessB: 16),
  _Graph4Row(name: 'AX', flex: 23.5, toneScore: 23, hardnessA: 14, hardnessB: 15),
  _Graph4Row(name: 'AY', flex: 19.6, toneScore: 22, hardnessA: 13, hardnessB: 13, ratingTag: 'S'),
  _Graph4Row(name: 'AZ', flex: 24.4, toneScore: 32, hardnessA: 14, hardnessB: 15, ratingTag: 'S'),
];
