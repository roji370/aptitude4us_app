import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/mock_test_model.dart';
import '../models/question_model.dart';
import '../models/answer_model.dart';
import '../services/mock_test_service.dart';
import 'results_page.dart';

/// The timed exam session screen.
///
/// Critical design decision: the timer recomputes from server-set [endAt]
/// on every tick and every app resume. We never decrement a local counter.
class ExamPage extends StatefulWidget {
  final MockTestModel test;
  final String attemptId;
  final List<String> questionOrder;
  final DateTime endAt;
  final String mode;

  const ExamPage({
    super.key,
    required this.test,
    required this.attemptId,
    required this.questionOrder,
    required this.endAt,
    required this.mode,
  });

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WidgetsBindingObserver {
  final MockTestService _service = MockTestService();

  // Questions
  Map<String, QuestionModel> _questions = {};
  Map<String, AnswerModel> _answers = {};
  bool _loadingQuestions = true;

  // Navigation
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  // Timer
  late Timer _timer;
  Duration _remaining = Duration.zero;

  // Submit state
  bool _submitting = false;

  // Practice mode grading
  Map<String, GradeAnswerResult> _gradedResults = {};
  Map<String, bool> _grading = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remaining = widget.endAt.difference(DateTime.now());
    _startTimer();
    _loadQuestions();
    _loadExistingAnswers();
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Recompute from server endAt on every resume
      _updateRemaining();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final diff = widget.endAt.difference(now);
    if (diff.isNegative) {
      _timer.cancel();
      _autoSubmit();
      return;
    }
    if (mounted) {
      setState(() {
        _remaining = diff;
      });
    }
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await _service.getQuestionsByIds(widget.questionOrder);
      if (mounted) {
        setState(() {
          _questions = questions;
          _loadingQuestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingQuestions = false);
      }
    }
  }

  Future<void> _loadExistingAnswers() async {
    try {
      final answers = await _service.getAnswers(widget.attemptId);
      if (mounted) {
        setState(() => _answers = answers);
      }
    } catch (_) {}
  }

  Future<void> _selectOption(String questionId, String optionId) async {
    setState(() {
      _answers[questionId] = AnswerModel(
        questionId: questionId,
        selectedOptionId: optionId,
        answeredAt: Timestamp.now(),
        flagged: _answers[questionId]?.flagged ?? false,
      );
    });

    // Write to Firestore (works offline via write queue)
    await _service.saveAnswer(
      attemptId: widget.attemptId,
      questionId: questionId,
      selectedOptionId: optionId,
    );

    // Practice mode: auto-grade
    if (widget.mode == 'practice' && !_gradedResults.containsKey(questionId)) {
      setState(() => _grading[questionId] = true);
      try {
        final result = await _service.gradeAnswer(
          attemptId: widget.attemptId,
          questionId: questionId,
        );
        if (mounted) {
          setState(() {
            _gradedResults[questionId] = result;
            _grading[questionId] = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _grading[questionId] = false);
        }
      }
    }
  }

  Future<void> _toggleFlag(String questionId) async {
    final current = _answers[questionId]?.flagged ?? false;
    setState(() {
      if (_answers.containsKey(questionId)) {
        _answers[questionId] = AnswerModel(
          questionId: questionId,
          selectedOptionId: _answers[questionId]!.selectedOptionId,
          answeredAt: _answers[questionId]!.answeredAt,
          isCorrect: _answers[questionId]!.isCorrect,
          flagged: !current,
        );
      }
    });
    await _service.toggleFlag(
      attemptId: widget.attemptId,
      questionId: questionId,
      flagged: !current,
    );
  }

  void _goToQuestion(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentIndex = index);
  }

  Future<void> _confirmSubmit() async {
    final unanswered = widget.questionOrder
        .where((qId) => !_answers.containsKey(qId))
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Test'),
        content: Text(
          unanswered > 0
              ? 'You have $unanswered unanswered question${unanswered > 1 ? 's' : ''}. Are you sure you want to submit?'
              : 'Are you sure you want to submit your test?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue Test'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _submitTest();
    }
  }

  Future<void> _autoSubmit() async {
    _submitTest();
  }

  Future<void> _submitTest() async {
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      final result = await _service.finishAttempt(widget.attemptId);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsPage(
            test: widget.test,
            attemptId: widget.attemptId,
            score: result.score,
            domainBreakdown: result.domainBreakdown,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timerColor = _remaining.inMinutes < 5
        ? Colors.red
        : _remaining.inMinutes < 15
            ? Colors.orange
            : theme.colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave Test?'),
            content: const Text(
                'The timer will keep running. You can resume later.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (shouldPop == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        // App Bar with timer
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Text(
                'Q ${_currentIndex + 1}/${widget.questionOrder.length}',
                style: const TextStyle(fontSize: 16),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: timerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, size: 18, color: timerColor),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(_remaining),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: timerColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _submitting ? null : _confirmSubmit,
              child: const Text('Submit'),
            ),
          ],
        ),

        body: _loadingQuestions
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Question navigator dots
                  SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      itemCount: widget.questionOrder.length,
                      itemBuilder: (context, i) {
                        final qId = widget.questionOrder[i];
                        final answered = _answers.containsKey(qId);
                        final flagged = _answers[qId]?.flagged ?? false;
                        final isCurrent = i == _currentIndex;

                        return GestureDetector(
                          onTap: () => _goToQuestion(i),
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : answered
                                      ? theme.colorScheme.primary
                                          .withOpacity(0.2)
                                      : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                              border: flagged
                                  ? Border.all(
                                      color: Colors.orange, width: 2)
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isCurrent
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Questions
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (i) =>
                          setState(() => _currentIndex = i),
                      itemCount: widget.questionOrder.length,
                      itemBuilder: (context, i) {
                        final qId = widget.questionOrder[i];
                        final question = _questions[qId];
                        if (question == null) {
                          return const Center(
                              child: Text('Question not available'));
                        }

                        final answer = _answers[qId];
                        final graded = _gradedResults[qId];
                        final isGrading = _grading[qId] ?? false;

                        return _QuestionView(
                          question: question,
                          selectedOptionId: answer?.selectedOptionId,
                          flagged: answer?.flagged ?? false,
                          gradeResult: graded,
                          isGrading: isGrading,
                          isPracticeMode: widget.mode == 'practice',
                          onSelectOption: (optId) =>
                              _selectOption(qId, optId),
                          onToggleFlag: () => _toggleFlag(qId),
                        );
                      },
                    ),
                  ),

                  // Bottom nav
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (_currentIndex > 0)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _goToQuestion(_currentIndex - 1),
                                icon:
                                    const Icon(Icons.arrow_back, size: 18),
                                label: const Text('Previous'),
                              ),
                            ),
                          if (_currentIndex > 0 &&
                              _currentIndex <
                                  widget.questionOrder.length - 1)
                            const SizedBox(width: 12),
                          if (_currentIndex <
                              widget.questionOrder.length - 1)
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _goToQuestion(_currentIndex + 1),
                                icon: const Icon(Icons.arrow_forward,
                                    size: 18),
                                label: const Text('Next'),
                              ),
                            ),
                          if (_currentIndex ==
                              widget.questionOrder.length - 1)
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    _submitting ? null : _confirmSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.primary,
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Text('Finish & Submit'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  final QuestionModel question;
  final String? selectedOptionId;
  final bool flagged;
  final GradeAnswerResult? gradeResult;
  final bool isGrading;
  final bool isPracticeMode;
  final ValueChanged<String> onSelectOption;
  final VoidCallback onToggleFlag;

  const _QuestionView({
    required this.question,
    this.selectedOptionId,
    this.flagged = false,
    this.gradeResult,
    this.isGrading = false,
    this.isPracticeMode = false,
    required this.onSelectOption,
    required this.onToggleFlag,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alreadyGraded = gradeResult != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flag button
          Row(
            children: [
              Chip(
                label: Text(question.domain,
                    style: const TextStyle(fontSize: 12)),
                backgroundColor: theme.colorScheme.primaryContainer,
                side: BorderSide.none,
              ),
              const Spacer(),
              IconButton(
                onPressed: onToggleFlag,
                icon: Icon(
                  flagged ? Icons.flag : Icons.flag_outlined,
                  color: flagged ? Colors.orange : Colors.grey,
                ),
                tooltip: 'Mark for review',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stem
          Text(
            question.stem,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 17,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Options
          ...question.options.map((opt) {
            final isSelected = selectedOptionId == opt.id;
            final isCorrect =
                alreadyGraded && opt.id == gradeResult!.correctOptionId;
            final isWrong = alreadyGraded && isSelected && !gradeResult!.isCorrect;

            Color? borderColor;
            Color? bgColor;
            if (alreadyGraded) {
              if (isCorrect) {
                borderColor = Colors.green;
                bgColor = Colors.green.shade50;
              } else if (isWrong) {
                borderColor = Colors.red;
                bgColor = Colors.red.shade50;
              }
            } else if (isSelected) {
              borderColor = theme.colorScheme.primary;
              bgColor = theme.colorScheme.primary.withOpacity(0.05);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: alreadyGraded ? null : () => onSelectOption(opt.id),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor ?? Colors.grey.shade300,
                      width: isSelected || isCorrect || isWrong ? 2 : 1,
                    ),
                    color: bgColor,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected && !alreadyGraded
                              ? theme.colorScheme.primary
                              : Colors.grey.shade200,
                        ),
                        child: Center(
                          child: alreadyGraded
                              ? Icon(
                                  isCorrect
                                      ? Icons.check
                                      : isWrong
                                          ? Icons.close
                                          : null,
                                  size: 18,
                                  color: isCorrect
                                      ? Colors.green
                                      : Colors.red,
                                )
                              : Text(
                                  opt.id,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey[700],
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          opt.text,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Practice mode: loading indicator
          if (isGrading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),

          // Practice mode: rationale
          if (alreadyGraded && gradeResult!.rationale != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, size: 20, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Explanation',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gradeResult!.rationale!,
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
