import 'package:flutter/material.dart';
import '../models/mock_test_model.dart';
import '../models/attempt_model.dart';
import '../services/mock_test_service.dart';
import 'answer_review_page.dart';

/// Results screen shown after submitting a test.
class ResultsPage extends StatelessWidget {
  final MockTestModel test;
  final String attemptId;
  final AttemptScore score;
  final Map<String, DomainScore> domainBreakdown;

  const ResultsPage({
    super.key,
    required this.test,
    required this.attemptId,
    required this.score,
    required this.domainBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passed = score.passed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Score circle
            const SizedBox(height: 16),
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: passed ? Colors.green.shade50 : Colors.red.shade50,
                border: Border.all(
                  color: passed ? Colors.green : Colors.red,
                  width: 4,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${score.percent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: passed ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  Text(
                    passed ? 'PASSED' : 'FAILED',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: passed ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Test title
            Text(
              test.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Score breakdown cards
            Row(
              children: [
                _ScoreCard(
                  label: 'Correct',
                  value: '${score.correct}',
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                _ScoreCard(
                  label: 'Incorrect',
                  value: '${score.incorrect}',
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                _ScoreCard(
                  label: 'Unanswered',
                  value: '${score.unanswered}',
                  color: Colors.grey,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Pass mark & negative marking info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _ResultRow(
                      label: 'Total Questions',
                      value: '${score.total}',
                    ),
                    const Divider(height: 16),
                    _ResultRow(
                      label: 'Pass Mark',
                      value: '${score.passMarkPercent}%',
                    ),
                    if (score.negativeMarkingApplied) ...[
                      const Divider(height: 16),
                      _ResultRow(
                        label: 'Raw Score',
                        value: score.rawScore.toStringAsFixed(2),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Domain breakdown
            if (domainBreakdown.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Performance by Domain',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...domainBreakdown.entries.map((entry) {
                final domain = entry.key;
                final ds = entry.value;
                final pct = ds.total > 0 ? (ds.correct / ds.total) : 0.0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              domain,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            '${ds.correct}/${ds.total}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: pct >= 0.5
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct >= 0.5 ? Colors.green : Colors.red,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 32),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnswerReviewPage(
                        attemptId: attemptId,
                        testTitle: test.title,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Review Answers'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  // Pop back to the mock tests home
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Back to Tests'),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ScoreCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

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
