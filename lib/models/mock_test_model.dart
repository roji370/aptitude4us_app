import 'package:cloud_firestore/cloud_firestore.dart';

/// A mock test definition — what students see on the test list.
class MockTestModel {
  final String id;
  final String title;
  final String description;
  final String tag;
  final List<TestSection> sections;
  final TestModes modes;
  final int durationMinutes;
  final int passMarkPercent;
  final NegativeMarking negativeMarking;
  final String status; // 'draft' | 'published' | 'archived'
  final TestStats? stats;
  final Timestamp? createdAt;

  MockTestModel({
    required this.id,
    required this.title,
    required this.description,
    required this.tag,
    required this.sections,
    required this.modes,
    required this.durationMinutes,
    required this.passMarkPercent,
    required this.negativeMarking,
    required this.status,
    this.stats,
    this.createdAt,
  });

  /// Total question count across all sections.
  int get totalQuestions =>
      sections.fold(0, (sum, s) => sum + s.questionIds.length);

  factory MockTestModel.fromJson(Map<String, dynamic> json, String id) {
    return MockTestModel(
      id: id,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      tag: json['tag'] ?? '',
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((s) => TestSection.fromJson(s as Map<String, dynamic>))
          .toList(),
      modes: TestModes.fromJson(json['modes'] as Map<String, dynamic>? ?? {}),
      durationMinutes: json['durationMinutes'] ?? 60,
      passMarkPercent: json['passMarkPercent'] ?? 50,
      negativeMarking: NegativeMarking.fromJson(
          json['negativeMarking'] as Map<String, dynamic>? ?? {}),
      status: json['status'] ?? 'draft',
      stats: json['stats'] != null
          ? TestStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] as Timestamp?,
    );
  }
}

class TestSection {
  final String name;
  final List<String> questionIds;

  TestSection({required this.name, required this.questionIds});

  factory TestSection.fromJson(Map<String, dynamic> json) {
    return TestSection(
      name: json['name'] ?? '',
      questionIds: List<String>.from(json['questionIds'] ?? []),
    );
  }
}

class TestModes {
  final bool exam;
  final bool practice;

  TestModes({required this.exam, required this.practice});

  factory TestModes.fromJson(Map<String, dynamic> json) {
    return TestModes(
      exam: json['exam'] ?? true,
      practice: json['practice'] ?? true,
    );
  }
}

class NegativeMarking {
  final bool enabled;
  final double penaltyPerWrong;

  NegativeMarking({required this.enabled, required this.penaltyPerWrong});

  factory NegativeMarking.fromJson(Map<String, dynamic> json) {
    return NegativeMarking(
      enabled: json['enabled'] ?? false,
      penaltyPerWrong: (json['penaltyPerWrong'] ?? 0).toDouble(),
    );
  }
}

class TestStats {
  final int attempts;
  final double avgScorePercent;
  final double passRatePercent;

  TestStats({
    required this.attempts,
    required this.avgScorePercent,
    required this.passRatePercent,
  });

  factory TestStats.fromJson(Map<String, dynamic> json) {
    return TestStats(
      attempts: json['attempts'] ?? 0,
      avgScorePercent: (json['avgScorePercent'] ?? 0).toDouble(),
      passRatePercent: (json['passRatePercent'] ?? 0).toDouble(),
    );
  }
}
