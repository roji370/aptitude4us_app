import 'package:cloud_firestore/cloud_firestore.dart';

/// A student's attempt at a mock test.
class AttemptModel {
  final String id;
  final String studentId;
  final String testId;
  final String mode; // 'exam' | 'practice'
  final String status; // 'in_progress' | 'submitted' | 'auto_submitted' | 'voided'
  final List<String> questionOrder;
  final Timestamp startedAt;
  final Timestamp endAt;
  final int extraSeconds;
  final Timestamp? submittedAt;
  final AttemptScore? score;
  final Map<String, DomainScore>? domainBreakdown;
  final String? voidReason;

  AttemptModel({
    required this.id,
    required this.studentId,
    required this.testId,
    required this.mode,
    required this.status,
    required this.questionOrder,
    required this.startedAt,
    required this.endAt,
    this.extraSeconds = 0,
    this.submittedAt,
    this.score,
    this.domainBreakdown,
    this.voidReason,
  });

  /// Whether this attempt is still in progress.
  bool get isInProgress => status == 'in_progress';

  /// Whether this attempt has been submitted (by student or auto).
  bool get isSubmitted =>
      status == 'submitted' || status == 'auto_submitted';

  /// Time remaining from now, recomputed from server endAt.
  Duration get timeRemaining {
    final end = endAt.toDate();
    final now = DateTime.now();
    final diff = end.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Whether time has expired.
  bool get isExpired => timeRemaining == Duration.zero;

  factory AttemptModel.fromJson(Map<String, dynamic> json, String id) {
    return AttemptModel(
      id: id,
      studentId: json['studentId'] ?? '',
      testId: json['testId'] ?? '',
      mode: json['mode'] ?? 'exam',
      status: json['status'] ?? 'in_progress',
      questionOrder: List<String>.from(json['questionOrder'] ?? []),
      startedAt: json['startedAt'] as Timestamp? ?? Timestamp.now(),
      endAt: json['endAt'] as Timestamp? ?? Timestamp.now(),
      extraSeconds: json['extraSeconds'] ?? 0,
      submittedAt: json['submittedAt'] as Timestamp?,
      score: json['score'] != null
          ? AttemptScore.fromJson(json['score'] as Map<String, dynamic>)
          : null,
      domainBreakdown: json['domainBreakdown'] != null
          ? (json['domainBreakdown'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(
                  k, DomainScore.fromJson(v as Map<String, dynamic>)))
          : null,
      voidReason: json['voidReason'],
    );
  }
}

class AttemptScore {
  final int correct;
  final int incorrect;
  final int unanswered;
  final int total;
  final double rawScore;
  final double percent;
  final bool passed;
  final int passMarkPercent;
  final bool negativeMarkingApplied;

  AttemptScore({
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.total,
    required this.rawScore,
    required this.percent,
    required this.passed,
    required this.passMarkPercent,
    required this.negativeMarkingApplied,
  });

  factory AttemptScore.fromJson(Map<String, dynamic> json) {
    return AttemptScore(
      correct: json['correct'] ?? 0,
      incorrect: json['incorrect'] ?? 0,
      unanswered: json['unanswered'] ?? 0,
      total: json['total'] ?? 0,
      rawScore: (json['rawScore'] ?? 0).toDouble(),
      percent: (json['percent'] ?? 0).toDouble(),
      passed: json['passed'] ?? false,
      passMarkPercent: json['passMarkPercent'] ?? 50,
      negativeMarkingApplied: json['negativeMarkingApplied'] ?? false,
    );
  }
}

class DomainScore {
  final int correct;
  final int total;

  DomainScore({required this.correct, required this.total});

  double get percent => total > 0 ? (correct / total) * 100 : 0;

  factory DomainScore.fromJson(Map<String, dynamic> json) {
    return DomainScore(
      correct: json['correct'] ?? 0,
      total: json['total'] ?? 0,
    );
  }
}
