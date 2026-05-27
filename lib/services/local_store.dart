import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cane.dart';
import '../models/reed.dart';

class LocalDatabaseSnapshot {
  const LocalDatabaseSnapshot({
    required this.caneSamples,
    required this.reedEvaluations,
  });

  final List<CaneSample> caneSamples;
  final List<ReedEvaluation> reedEvaluations;
}

class LocalStore {
  static const String _dbKey = 'bassoon_cane_db_json';

  Future<LocalDatabaseSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final content = prefs.getString(_dbKey);
    if (content == null || content.trim().isEmpty) {
      return const LocalDatabaseSnapshot(caneSamples: [], reedEvaluations: []);
    }

    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    final caneRaw = jsonMap['caneSamples'] as List<dynamic>? ?? const [];
    final reedRaw = jsonMap['reedEvaluations'] as List<dynamic>? ?? const [];

    return LocalDatabaseSnapshot(
      caneSamples: caneRaw
          .map((item) => CaneSample.fromJson(item as Map<String, dynamic>))
          .toList(),
      reedEvaluations: reedRaw
          .map((item) => ReedEvaluation.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> save({
    required List<CaneSample> caneSamples,
    required List<ReedEvaluation> reedEvaluations,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'caneSamples': caneSamples.map((item) => item.toJson()).toList(),
      'reedEvaluations': reedEvaluations.map((item) => item.toJson()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(
      _dbKey,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}

class SyncGateway {
  Future<void> syncNow({
    required List<CaneSample> caneSamples,
    required List<ReedEvaluation> reedEvaluations,
  }) async {
    // Placeholder for Firebase/Supabase sync implementation.
    // The app is local-first, so this no-op keeps MVP working offline.
    return;
  }
}
