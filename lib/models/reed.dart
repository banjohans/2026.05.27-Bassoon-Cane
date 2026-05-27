class ReedEvaluation {
  ReedEvaluation({
    required this.id,
    required this.caneId,
    required this.createdAt,
    required this.response,
    required this.stability,
    required this.tone,
    required this.intonation,
    required this.flexibility,
    required this.projection,
    required this.resistance,
    this.comment = '',
    this.goldStandard = false,
    this.longevityDays,
    this.photoPaths = const [],
  });

  final String id;
  final String caneId;
  final DateTime createdAt;
  final int response;
  final int stability;
  final int tone;
  final int intonation;
  final int flexibility;
  final int projection;
  final int resistance;
  final String comment;
  final bool goldStandard;
  final int? longevityDays;
  final List<String> photoPaths;

  ReedEvaluation copyWith({
    String? caneId,
    int? response,
    int? stability,
    int? tone,
    int? intonation,
    int? flexibility,
    int? projection,
    int? resistance,
    String? comment,
    bool? goldStandard,
    int? longevityDays,
    List<String>? photoPaths,
  }) {
    return ReedEvaluation(
      id: id,
      caneId: caneId ?? this.caneId,
      createdAt: createdAt,
      response: response ?? this.response,
      stability: stability ?? this.stability,
      tone: tone ?? this.tone,
      intonation: intonation ?? this.intonation,
      flexibility: flexibility ?? this.flexibility,
      projection: projection ?? this.projection,
      resistance: resistance ?? this.resistance,
      comment: comment ?? this.comment,
      goldStandard: goldStandard ?? this.goldStandard,
      longevityDays: longevityDays ?? this.longevityDays,
      photoPaths: photoPaths ?? this.photoPaths,
    );
  }

  double get overallScore {
    final sum = response +
        stability +
        tone +
        intonation +
        flexibility +
        projection +
        resistance;
    return sum / 7;
  }

  bool get isSuccessful => overallScore >= 8;

  // Internationalized grade scale anchored to the existing 1-10 score model.
  static String gradeForScore(double score) {
    final normalized = score.clamp(1, 10).toDouble();
    if (normalized >= 9.5) {
      return 'A+';
    }
    if (normalized >= 8.5) {
      return 'A';
    }
    if (normalized >= 7.5) {
      return 'A-';
    }
    if (normalized >= 6.5) {
      return 'B+';
    }
    if (normalized >= 5.5) {
      return 'B';
    }
    if (normalized >= 4.5) {
      return 'B-';
    }
    if (normalized >= 3.5) {
      return 'C+';
    }
    if (normalized >= 2.5) {
      return 'C';
    }
    if (normalized >= 1.5) {
      return 'C-';
    }
    return 'D';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caneId': caneId,
      'createdAt': createdAt.toIso8601String(),
      'response': response,
      'stability': stability,
      'tone': tone,
      'intonation': intonation,
      'flexibility': flexibility,
      'projection': projection,
      'resistance': resistance,
      'comment': comment,
      'goldStandard': goldStandard,
      'longevityDays': longevityDays,
      'photoPaths': photoPaths,
    };
  }

  factory ReedEvaluation.fromJson(Map<String, dynamic> json) {
    return ReedEvaluation(
      id: json['id'] as String,
      caneId: json['caneId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      response: (json['response'] as num?)?.toInt() ?? 1,
      stability: (json['stability'] as num?)?.toInt() ?? 1,
      tone: (json['tone'] as num?)?.toInt() ?? 1,
      intonation: (json['intonation'] as num?)?.toInt() ?? 1,
      flexibility: (json['flexibility'] as num?)?.toInt() ?? 1,
      projection: (json['projection'] as num?)?.toInt() ?? 1,
      resistance: (json['resistance'] as num?)?.toInt() ?? 1,
      comment: json['comment'] as String? ?? '',
        goldStandard: json['goldStandard'] as bool? ?? false,
      longevityDays: (json['longevityDays'] as num?)?.toInt(),
      photoPaths: (json['photoPaths'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}
