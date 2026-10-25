import 'package:flutter/material.dart';
import '../models/mock_test_model.dart';
import '../models/attempt_model.dart';
import '../services/mock_test_service.dart';
import '../utils/app_colors.dart';
import 'test_detail_page.dart';

/// Mock Tests home screen with "New" and "Attended" tabs.
class MockTestsHomePage extends StatefulWidget {
  const MockTestsHomePage({super.key});

  @override
  State<MockTestsHomePage> createState() => _MockTestsHomePageState();
}

class _MockTestsHomePageState extends State<MockTestsHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MockTestService _service = MockTestService();

  List<MockTestModel> _availableTests = [];
  List<AttemptModel> _myAttempts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getAvailableTests(),
        _service.getMyAttempts(),
      ]);

      setState(() {
        _availableTests = results[0] as List<MockTestModel>;
        _myAttempts = results[1] as List<AttemptModel>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load tests. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mock Tests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Available'),
            Tab(text: 'My Attempts'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: Colors.red[700])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAvailableTab(),
                    _buildAttemptsTab(),
                  ],
                ),
    );
  }

  Widget _buildAvailableTab() {
    if (_availableTests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No tests available',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Check back later for new mock tests',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _availableTests.length,
        itemBuilder: (context, index) {
          final test = _availableTests[index];
          // Check if there's an in-progress attempt for this test
          final inProgressAttempt = _myAttempts
              .where((a) => a.testId == test.id && a.isInProgress)
              .firstOrNull;

          return _TestCard(
            test: test,
            inProgressAttempt: inProgressAttempt,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TestDetailPage(
                  test: test,
                  existingAttempt: inProgressAttempt,
                ),
              ),
            ).then((_) => _loadData()),
          );
        },
      ),
    );
  }

  Widget _buildAttemptsTab() {
    final completedAttempts = _myAttempts.where((a) => a.isSubmitted).toList();

    if (completedAttempts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No completed attempts',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: completedAttempts.length,
        itemBuilder: (context, index) {
          final attempt = completedAttempts[index];
          return _AttemptCard(
            attempt: attempt,
            testTitle: _availableTests
                .where((t) => t.id == attempt.testId)
                .firstOrNull
                ?.title,
          );
        },
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  final MockTestModel test;
  final AttemptModel? inProgressAttempt;
  final VoidCallback onTap;

  const _TestCard({
    required this.test,
    this.inProgressAttempt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      test.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (inProgressAttempt != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'In Progress',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (test.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  test.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: '${test.durationMinutes} min',
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.quiz_outlined,
                    label: '${test.totalQuestions} Q',
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.check_circle_outline,
                    label: '${test.passMarkPercent}% pass',
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _AttemptCard extends StatelessWidget {
  final AttemptModel attempt;
  final String? testTitle;

  const _AttemptCard({
    required this.attempt,
    this.testTitle,
  });

  @override
  Widget build(BuildContext context) {
    final passed = attempt.score?.passed ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: passed ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${attempt.score?.percent.toStringAsFixed(0) ?? '—'}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: passed ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    testTitle ?? 'Test ${attempt.testId.substring(0, 8)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${attempt.score?.correct ?? 0}/${attempt.score?.total ?? 0} correct • ${attempt.mode} mode',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(
                passed ? 'PASS' : 'FAIL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: passed ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              backgroundColor: passed ? Colors.green.shade50 : Colors.red.shade50,
              side: BorderSide.none,
            ),
          ],
        ),
      ),
    );
  }
}
