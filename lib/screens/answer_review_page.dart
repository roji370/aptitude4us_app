import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../models/question_model.dart';

/// Per-question review with correct answer, student answer, and rationale.
class AnswerReviewPage extends StatefulWidget {
  final String attemptId;
  final String testTitle;

  const AnswerReviewPage({
    super.key,
    required this.attemptId,
    required this.testTitle,
  });

  @override
  State<AnswerReviewPage> createState() => _AnswerReviewPageState();
}

class _AnswerReviewPageState extends State<AnswerReviewPage> {
  final MockTestService _service = MockTestService();
  AttemptReviewResult? _review;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReview();
  }

  Future<void> _loadReview() async {
    try {
      final review = await _service.getAttemptReview(widget.attemptId);
      if (mounted) {
        setState(() {
          _review = review;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load review: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Review: ${widget.testTitle}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _loadReview,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildReviewList(),
    );
  }

  Widget _buildReviewList() {
    final questions = _review!.questions;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final q = questions[index];
        return _ReviewQuestionCard(
          index: index + 1,
          question: q,
        );
      },
    );
  }
}

class _ReviewQuestionCard extends StatelessWidget {
  final int index;
  final ReviewQuestion question;

  const _ReviewQuestionCard({
    required this.index,
    required this.question,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCorrect = question.isCorrect == true;
    final isUnanswered = question.selectedOptionId == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isUnanswered
                        ? Colors.grey.shade200
                        : isCorrect
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                  ),
                  child: Center(
                    child: isUnanswered
                        ? Text('$index',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700]))
                        : Icon(
                            isCorrect ? Icons.check : Icons.close,
                            size: 18,
                            color: isCorrect ? Colors.green : Colors.red,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Question $index',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Chip(
                  label: Text(
                    question.domain,
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Stem
            Text(
              question.stem,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),

            const SizedBox(height: 12),

            // Options
            ...question.options.map((opt) {
              final isStudentAnswer = opt.id == question.selectedOptionId;
              final isCorrectAnswer = opt.id == question.correctOptionId;

              Color? bg;
              Color? border;
              if (isCorrectAnswer) {
                bg = Colors.green.shade50;
                border = Colors.green;
              } else if (isStudentAnswer && !isCorrect) {
                bg = Colors.red.shade50;
                border = Colors.red;
              }

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: bg,
                  border: Border.all(
                    color: border ?? Colors.grey.shade300,
                    width: (isCorrectAnswer || isStudentAnswer) ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      opt.id,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCorrectAnswer
                            ? Colors.green.shade700
                            : isStudentAnswer
                                ? Colors.red.shade700
                                : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(opt.text, style: const TextStyle(fontSize: 14)),
                    ),
                    if (isCorrectAnswer)
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    if (isStudentAnswer && !isCorrectAnswer)
                      const Icon(Icons.cancel, color: Colors.red, size: 20),
                  ],
                ),
              );
            }),

            // Rationale
            if (question.rationale != null &&
                question.rationale!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb,
                            size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Explanation',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      question.rationale!,
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
