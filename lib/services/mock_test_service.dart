import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/mock_test_model.dart';
import '../models/question_model.dart';
import '../models/attempt_model.dart';
import '../models/answer_model.dart';
import '../utils/logger.dart';

/// Service for mock test operations.
///
/// Design principle: reads are direct Firestore queries (cheap, offline-capable);
/// anything that affects grading or timing integrity goes through a Cloud Function.
class MockTestService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  MockTestService()
      : _firestore = FirebaseFirestore.instance,
        _functions = FirebaseFunctions.instance,
        _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  // ═══════════════════════════════════════════════════════════════════════
  // TESTS — Direct Firestore Reads
  // ═══════════════════════════════════════════════════════════════════════

  /// Fetch all published tests available to this student.
  Future<List<MockTestModel>> getAvailableTests() async {
    try {
      final snap = await _firestore
          .collection('tests')
          .where('status', isEqualTo: 'published')
          .orderBy('createdAt', descending: true)
          .get();

      final now = DateTime.now();
      return snap.docs
          .map((doc) => MockTestModel.fromJson(
              doc.data(), doc.id))
          .where((test) {
        // Client-side availability filtering
        // (Firestore can't query nested Timestamp ranges efficiently)
        return true; // All published tests are potentially available;
        // startAttempt does the authoritative check server-side.
      }).toList();
    } catch (e) {
      Logger.e('Error fetching available tests: $e');
      return [];
    }
  }

  /// Fetch a single test by ID.
  Future<MockTestModel?> getTest(String testId) async {
    try {
      final doc = await _firestore.collection('tests').doc(testId).get();
      if (!doc.exists) return null;
      return MockTestModel.fromJson(doc.data()!, doc.id);
    } catch (e) {
      Logger.e('Error fetching test $testId: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // QUESTIONS — Direct Firestore Reads
  // ═══════════════════════════════════════════════════════════════════════

  /// Fetch questions by IDs (for rendering during an exam).
  Future<Map<String, QuestionModel>> getQuestionsByIds(
      List<String> questionIds) async {
    if (questionIds.isEmpty) return {};

    try {
      final Map<String, QuestionModel> result = {};

      // Firestore 'in' queries are limited to 30 items
      for (int i = 0; i < questionIds.length; i += 30) {
        final chunk = questionIds.sublist(
            i, i + 30 > questionIds.length ? questionIds.length : i + 30);

        final snap = await _firestore
            .collection('questions')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          result[doc.id] = QuestionModel.fromJson(doc.data(), doc.id);
        }
      }

      return result;
    } catch (e) {
      Logger.e('Error fetching questions: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ATTEMPTS — Direct Firestore Reads
  // ═══════════════════════════════════════════════════════════════════════

  /// Get this student's attempts (for history / "Attended" tab).
  Future<List<AttemptModel>> getMyAttempts() async {
    final uid = _currentUserId;
    if (uid == null) return [];

    try {
      final snap = await _firestore
          .collection('attempts')
          .where('studentId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs
          .map((doc) => AttemptModel.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      Logger.e('Error fetching my attempts: $e');
      return [];
    }
  }

  /// Check if there's an existing in_progress attempt for a test.
  Future<AttemptModel?> getInProgressAttempt(String testId) async {
    final uid = _currentUserId;
    if (uid == null) return null;

    try {
      final snap = await _firestore
          .collection('attempts')
          .where('studentId', isEqualTo: uid)
          .where('testId', isEqualTo: testId)
          .where('status', isEqualTo: 'in_progress')
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;
      return AttemptModel.fromJson(snap.docs.first.data(), snap.docs.first.id);
    } catch (e) {
      Logger.e('Error checking in-progress attempt: $e');
      return null;
    }
  }

  /// Get a single attempt by ID.
  Future<AttemptModel?> getAttempt(String attemptId) async {
    try {
      final doc =
          await _firestore.collection('attempts').doc(attemptId).get();
      if (!doc.exists) return null;
      return AttemptModel.fromJson(doc.data()!, doc.id);
    } catch (e) {
      Logger.e('Error fetching attempt $attemptId: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ANSWERS — Direct Firestore Writes (security rules allow this)
  // ═══════════════════════════════════════════════════════════════════════

  /// Save/update a student's answer selection.
  /// Works offline via Firestore's built-in write queue.
  Future<void> saveAnswer({
    required String attemptId,
    required String questionId,
    required String selectedOptionId,
  }) async {
    try {
      await _firestore
          .collection('attempts')
          .doc(attemptId)
          .collection('answers')
          .doc(questionId)
          .set({
        'selectedOptionId': selectedOptionId,
        'answeredAt': FieldValue.serverTimestamp(),
        'isCorrect': null, // Only set by gradeAnswer in practice mode
        'flagged': false,
      }, SetOptions(merge: true));
    } catch (e) {
      Logger.e('Error saving answer: $e');
      rethrow;
    }
  }

  /// Toggle the flagged/mark-for-review state.
  Future<void> toggleFlag({
    required String attemptId,
    required String questionId,
    required bool flagged,
  }) async {
    try {
      await _firestore
          .collection('attempts')
          .doc(attemptId)
          .collection('answers')
          .doc(questionId)
          .set({'flagged': flagged}, SetOptions(merge: true));
    } catch (e) {
      Logger.e('Error toggling flag: $e');
    }
  }

  /// Get all answers for an attempt (for the question navigator dots).
  Future<Map<String, AnswerModel>> getAnswers(String attemptId) async {
    try {
      final snap = await _firestore
          .collection('attempts')
          .doc(attemptId)
          .collection('answers')
          .get();

      final Map<String, AnswerModel> result = {};
      for (final doc in snap.docs) {
        result[doc.id] = AnswerModel.fromJson(doc.data(), doc.id);
      }
      return result;
    } catch (e) {
      Logger.e('Error fetching answers: $e');
      return {};
    }
  }

  /// Stream answers in real-time (for sync indicator).
  Stream<Map<String, AnswerModel>> streamAnswers(String attemptId) {
    return _firestore
        .collection('attempts')
        .doc(attemptId)
        .collection('answers')
        .snapshots()
        .map((snap) {
      final Map<String, AnswerModel> result = {};
      for (final doc in snap.docs) {
        result[doc.id] = AnswerModel.fromJson(doc.data(), doc.id);
      }
      return result;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CLOUD FUNCTIONS — Integrity-sensitive operations
  // ═══════════════════════════════════════════════════════════════════════

  /// Start or resume an attempt. Idempotent — returns existing if one exists.
  Future<StartAttemptResult> startAttempt({
    required String testId,
    required String mode,
  }) async {
    try {
      final callable = _functions.httpsCallable('startAttempt');
      final result = await callable.call({
        'testId': testId,
        'mode': mode,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return StartAttemptResult(
        attemptId: data['attemptId'],
        questionOrder: List<String>.from(data['questionOrder']),
        startedAt: DateTime.parse(data['startedAt']),
        endAt: DateTime.parse(data['endAt']),
        mode: data['mode'],
        resumed: data['resumed'] ?? false,
      );
    } catch (e) {
      Logger.e('Error starting attempt: $e');
      rethrow;
    }
  }

  /// Grade a single answer in practice mode. Needs connectivity.
  Future<GradeAnswerResult> gradeAnswer({
    required String attemptId,
    required String questionId,
  }) async {
    try {
      final callable = _functions.httpsCallable('gradeAnswer');
      final result = await callable.call({
        'attemptId': attemptId,
        'questionId': questionId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return GradeAnswerResult(
        isCorrect: data['isCorrect'],
        correctOptionId: data['correctOptionId'],
        rationale: data['rationale'],
        distractorNotes: data['distractorNotes'] != null
            ? Map<String, String>.from(data['distractorNotes'])
            : null,
      );
    } catch (e) {
      Logger.e('Error grading answer: $e');
      rethrow;
    }
  }

  /// Submit the attempt for grading. Returns the full results payload.
  Future<FinishAttemptResult> finishAttempt(String attemptId) async {
    try {
      final callable = _functions.httpsCallable('finishAttempt');
      final result = await callable.call({'attemptId': attemptId});

      final data = Map<String, dynamic>.from(result.data as Map);
      final scoreData = Map<String, dynamic>.from(data['score'] as Map);
      final domainRaw = data['domainBreakdown'] as Map?;
      final domainData = domainRaw != null
          ? Map<String, dynamic>.from(domainRaw)
          : <String, dynamic>{};

      return FinishAttemptResult(
        attemptId: data['attemptId'],
        status: data['status'],
        score: AttemptScore(
          correct: scoreData['correct'],
          incorrect: scoreData['incorrect'],
          unanswered: scoreData['unanswered'],
          total: scoreData['total'],
          rawScore: (scoreData['rawScore'] ?? 0).toDouble(),
          percent: (scoreData['percent'] ?? 0).toDouble(),
          passed: scoreData['passed'],
          passMarkPercent: scoreData['passMarkPercent'] ?? 50,
          negativeMarkingApplied:
              scoreData['negativeMarkingApplied'] ?? false,
        ),
        domainBreakdown: domainData.map((k, v) {
          final d = Map<String, dynamic>.from(v as Map);
          return MapEntry(
              k, DomainScore(correct: d['correct'], total: d['total']));
        }),
        alreadySubmitted: data['alreadySubmitted'] ?? false,
      );
    } catch (e) {
      Logger.e('Error finishing attempt: $e');
      rethrow;
    }
  }

  /// Get the full review for a submitted attempt (questions + correct answers).
  Future<AttemptReviewResult> getAttemptReview(String attemptId) async {
    try {
      final callable = _functions.httpsCallable('getAttemptReview');
      final result = await callable.call({'attemptId': attemptId});

      final data = Map<String, dynamic>.from(result.data as Map);
      final questions = (data['questions'] as List<dynamic>)
          .map((q) => ReviewQuestion.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList();

      final scoreRaw = data['score'] as Map?;
      final scoreData = scoreRaw != null
          ? Map<String, dynamic>.from(scoreRaw)
          : null;
      final domainRaw = data['domainBreakdown'] as Map?;
      final domainData = domainRaw != null
          ? Map<String, dynamic>.from(domainRaw)
          : <String, dynamic>{};

      return AttemptReviewResult(
        attemptId: data['attemptId'],
        testId: data['testId'],
        mode: data['mode'],
        score: scoreData != null
            ? AttemptScore(
                correct: scoreData['correct'],
                incorrect: scoreData['incorrect'],
                unanswered: scoreData['unanswered'],
                total: scoreData['total'],
                rawScore: (scoreData['rawScore'] ?? 0).toDouble(),
                percent: (scoreData['percent'] ?? 0).toDouble(),
                passed: scoreData['passed'],
                passMarkPercent: scoreData['passMarkPercent'] ?? 50,
                negativeMarkingApplied:
                    scoreData['negativeMarkingApplied'] ?? false,
              )
            : null,
        domainBreakdown: domainData.map((k, v) {
          final d = Map<String, dynamic>.from(v as Map);
          return MapEntry(
              k, DomainScore(correct: d['correct'], total: d['total']));
        }),
        startedAt: data['startedAt'],
        submittedAt: data['submittedAt'],
        questions: questions,
      );
    } catch (e) {
      Logger.e('Error getting attempt review: $e');
      rethrow;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Result DTOs for Cloud Function responses
// ═══════════════════════════════════════════════════════════════════════════

class StartAttemptResult {
  final String attemptId;
  final List<String> questionOrder;
  final DateTime startedAt;
  final DateTime endAt;
  final String mode;
  final bool resumed;

  StartAttemptResult({
    required this.attemptId,
    required this.questionOrder,
    required this.startedAt,
    required this.endAt,
    required this.mode,
    required this.resumed,
  });
}

class GradeAnswerResult {
  final bool isCorrect;
  final String correctOptionId;
  final String? rationale;
  final Map<String, String>? distractorNotes;

  GradeAnswerResult({
    required this.isCorrect,
    required this.correctOptionId,
    this.rationale,
    this.distractorNotes,
  });
}

class FinishAttemptResult {
  final String attemptId;
  final String status;
  final AttemptScore score;
  final Map<String, DomainScore> domainBreakdown;
  final bool alreadySubmitted;

  FinishAttemptResult({
    required this.attemptId,
    required this.status,
    required this.score,
    required this.domainBreakdown,
    required this.alreadySubmitted,
  });
}

class AttemptReviewResult {
  final String attemptId;
  final String testId;
  final String mode;
  final AttemptScore? score;
  final Map<String, DomainScore> domainBreakdown;
  final String? startedAt;
  final String? submittedAt;
  final List<ReviewQuestion> questions;

  AttemptReviewResult({
    required this.attemptId,
    required this.testId,
    required this.mode,
    this.score,
    required this.domainBreakdown,
    this.startedAt,
    this.submittedAt,
    required this.questions,
  });
}

class ReviewQuestion {
  final String questionId;
  final String stem;
  final List<QuestionOption> options;
  final QuestionContext? context;
  final String domain;
  final String? difficulty;
  final String? selectedOptionId;
  final bool flagged;
  final String? correctOptionId;
  final bool? isCorrect;
  final String? rationale;
  final Map<String, String>? distractorNotes;

  ReviewQuestion({
    required this.questionId,
    required this.stem,
    required this.options,
    this.context,
    required this.domain,
    this.difficulty,
    this.selectedOptionId,
    this.flagged = false,
    this.correctOptionId,
    this.isCorrect,
    this.rationale,
    this.distractorNotes,
  });

  factory ReviewQuestion.fromJson(Map<String, dynamic> json) {
    return ReviewQuestion(
      questionId: json['questionId'] ?? '',
      stem: json['stem'] ?? '',
      options: (json['options'] as List<dynamic>? ?? [])
          .map((o) => QuestionOption.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList(),
      context: json['context'] != null
          ? QuestionContext.fromJson(Map<String, dynamic>.from(json['context'] as Map))
          : null,
      domain: json['domain'] ?? 'Unknown',
      difficulty: json['difficulty'],
      selectedOptionId: json['selectedOptionId'],
      flagged: json['flagged'] ?? false,
      correctOptionId: json['correctOptionId'],
      isCorrect: json['isCorrect'],
      rationale: json['rationale'],
      distractorNotes: json['distractorNotes'] != null
          ? Map<String, String>.from(json['distractorNotes'])
          : null,
    );
  }
}
