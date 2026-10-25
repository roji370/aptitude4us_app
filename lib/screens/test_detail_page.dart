import 'package:flutter/material.dart';
import '../models/mock_test_model.dart';
import '../models/attempt_model.dart';
import '../services/mock_test_service.dart';
import 'exam_page.dart';

/// Test info screen — shows details, Exam/Practice toggle, Start/Resume button.
class TestDetailPage extends StatefulWidget {
  final MockTestModel test;
  final AttemptModel? existingAttempt;

  const TestDetailPage({
    super.key,
    required this.test,
    this.existingAttempt,
  });

  @override
  State<TestDetailPage> createState() => _TestDetailPageState();
}

class _TestDetailPageState extends State<TestDetailPage> {
  final MockTestService _service = MockTestService();
  String _selectedMode = 'exam';
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existingAttempt != null) {
      _selectedMode = widget.existingAttempt!.mode;
    } else if (!widget.test.modes.exam && widget.test.modes.practice) {
      _selectedMode = 'practice';
    }
  }

  Future<void> _startTest() async {
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final result = await _service.startAttempt(
        testId: widget.test.id,
        mode: _selectedMode,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ExamPage(
            test: widget.test,
            attemptId: result.attemptId,
            questionOrder: result.questionOrder,
            endAt: result.endAt,
            mode: result.mode,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _starting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInProgress = widget.existingAttempt != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Tag
            Text(
              widget.test.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.test.tag.isNotEmpty) ...[
              const SizedBox(height: 8),
              Chip(
                label: Text(widget.test.tag),
                backgroundColor: theme.colorScheme.primaryContainer,
              ),
            ],

            // Description
            if (widget.test.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                widget.test.description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[700],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Stats row
            Row(
              children: [
                _StatCard(
                  icon: Icons.timer_outlined,
                  value: '${widget.test.durationMinutes}',
                  label: 'Minutes',
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.quiz_outlined,
                  value: '${widget.test.totalQuestions}',
                  label: 'Questions',
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.check_circle_outline,
                  value: '${widget.test.passMarkPercent}%',
                  label: 'Pass Mark',
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Config info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Test Information',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Negative Marking',
                      value: widget.test.negativeMarking.enabled
                          ? '-${widget.test.negativeMarking.penaltyPerWrong} per wrong answer'
                          : 'Not applied',
                    ),
                    const Divider(height: 16),
                    _InfoRow(
                      label: 'Sections',
                      value: '${widget.test.sections.length}',
                    ),
                    if (widget.test.stats != null) ...[
                      const Divider(height: 16),
                      _InfoRow(
                        label: 'Previous Attempts',
                        value: '${widget.test.stats!.attempts}',
                      ),
                      const Divider(height: 16),
                      _InfoRow(
                        label: 'Average Score',
                        value:
                            '${widget.test.stats!.avgScorePercent.toStringAsFixed(1)}%',
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Mode selection (only if test supports both)
            if (widget.test.modes.exam && widget.test.modes.practice && !hasInProgress) ...[
              Text('Select Mode',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      title: 'Exam Mode',
                      description: 'Timed test. Results at the end.',
                      icon: Icons.school_outlined,
                      selected: _selectedMode == 'exam',
                      onTap: () => setState(() => _selectedMode = 'exam'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ModeCard(
                      title: 'Practice Mode',
                      description: 'Instant feedback per question.',
                      icon: Icons.lightbulb_outlined,
                      selected: _selectedMode == 'practice',
                      onTap: () => setState(() => _selectedMode = 'practice'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Error
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Start / Resume button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _starting ? null : _startTest,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _starting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        hasInProgress ? 'Resume Test' : 'Start Test',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
              ),
            ),

            if (hasInProgress) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'You have an in-progress attempt. Time is still running.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700),
              ),
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.05)
              : Colors.white,
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 32,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey[500]),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
