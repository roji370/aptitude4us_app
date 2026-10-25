import 'package:cloud_firestore/cloud_firestore.dart';

/// A student's answer to a single question within an attempt.
/// Written directly to Firestore by the client (allowed by security rules
/// while the parent attempt is in_progress).
class AnswerModel {
  final String questionId;
  final String selectedOptionId;
  final Timestamp answeredAt;
  final bool? isCorrect; // Only populated in practice mode by gradeAnswer
  final bool flagged;

  AnswerModel({
    required this.questionId,
    required this.selectedOptionId,
    required this.answeredAt,
    this.isCorrect,
    this.flagged = false,
  });

  factory AnswerModel.fromJson(Map<String, dynamic> json, String questionId) {
    return AnswerModel(
      questionId: questionId,
      selectedOptionId: json['selectedOptionId'] ?? '',
      answeredAt: json['answeredAt'] as Timestamp? ?? Timestamp.now(),
      isCorrect: json['isCorrect'] as bool?,
      flagged: json['flagged'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selectedOptionId': selectedOptionId,
      'answeredAt': answeredAt,
      'isCorrect': isCorrect,
      'flagged': flagged,
    };
  }
}
