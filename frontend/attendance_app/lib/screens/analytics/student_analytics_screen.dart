import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';

class StudentAnalyticsScreen extends StatefulWidget {
  const StudentAnalyticsScreen({super.key});

  @override
  State<StudentAnalyticsScreen> createState() => _StudentAnalyticsScreenState();
}

class _StudentAnalyticsScreenState extends State<StudentAnalyticsScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _analyticsService.getStudentAnalytics();
      if (!mounted) return;
      if (res != null) {
        setState(() {
          _data = res;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Unable to load analytics. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'safe':
        return const Color(0xFF10B981); // Emerald
      case 'warning':
        return const Color(0xFFF59E0B); // Amber
      case 'critical':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'My Attendance Analytics',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchAnalytics,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF007C91)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 54, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchAnalytics,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007C91),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final overview = _data?['overview'] as Map<String, dynamic>? ?? {};
    final classesList = (_data?['classes_analytics'] as List<dynamic>? ?? []);
    final recentActivity = (_data?['recent_activity'] as List<dynamic>? ?? []);

    return RefreshIndicator(
      onRefresh: _fetchAnalytics,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          _buildOverviewHero(overview),
          const SizedBox(height: 20),
          _buildRecoveryActionCard(classesList),
          _buildSubjectsBreakdown(classesList),
          const SizedBox(height: 24),
          if (recentActivity.isNotEmpty) ...[
            _buildRecentActivitySection(recentActivity),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewHero(Map<String, dynamic> overview) {
    final overallRate = (overview['overall_rate'] as num?)?.toDouble() ?? 0.0;
    final attended = overview['attended_sessions'] ?? 0;
    final total = overview['total_conducted_sessions'] ?? 0;
    final streak = overview['streak'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007C91), Color(0xFF0097A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007C91).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: CircularProgressIndicator(
                      value: (overallRate / 100).clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 9,
                    ),
                  ),
                  Text(
                    '${overallRate.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Attendance',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$attended of $total Sessions Attended',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '75% required for examination eligibility',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (streak > 0) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$streak Consecutive Class${streak > 1 ? 'es' : ''} Attended Streak!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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

  Widget _buildRecoveryActionCard(List<dynamic> classesList) {
    final shortageSubjects = classesList.where((c) {
      final total = c['total_sessions'] ?? 0;
      final rate = (c['attendance_rate'] as num?)?.toDouble() ?? 0.0;
      return total > 0 && rate < 75.0;
    }).toList();

    // If no subjects have shortage, do not show any card
    if (shortageSubjects.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.priority_high_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recovery Action Required',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      Text(
                        '${shortageSubjects.length} subject${shortageSubjects.length > 1 ? 's have' : ' has'} attendance shortage below 75%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shortageSubjects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final c = shortageSubjects[idx];
                final code = c['class_code'] ?? '';
                final name = c['class_name'] ?? '';
                final rate = (c['attendance_rate'] as num?)?.toDouble() ?? 0.0;
                final attended = c['attended'] ?? 0;
                final total = c['total_sessions'] ?? 0;
                final needed = c['classes_needed'] ?? 0;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFEE2E2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              code,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Color(0xFF1E293B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${rate.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Current: $attended / $total sessions attended\n'
                        'Action: Must attend next $needed consecutive class${needed > 1 ? 'es' : ''} to reach 75%.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7F1D1D),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsBreakdown(List<dynamic> classesList) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.menu_book_rounded, color: Color(0xFF007C91), size: 22),
              SizedBox(width: 10),
              Text(
                'Subject-wise Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (classesList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'You are not enrolled in any classes yet.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: classesList.length,
              separatorBuilder: (_, __) => const Divider(height: 24, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, idx) {
                final c = classesList[idx];
                final code = c['class_code'] ?? '';
                final name = c['class_name'] ?? '';
                final teacher = c['teacher_name'] ?? '';
                final rate = (c['attendance_rate'] as num?)?.toDouble() ?? 0.0;
                final attended = c['attended'] ?? 0;
                final total = c['total_sessions'] ?? 0;
                final status = c['status'] as String? ?? 'Safe';
                final safeSkips = c['safe_skips'] ?? 0;
                final needed = c['classes_needed'] ?? 0;

                final color = _getStatusColor(status);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007C91).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF007C91),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (teacher.isNotEmpty)
                                Text(
                                  'Prof. $teacher',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          total > 0 ? '${rate.toStringAsFixed(1)}%' : 'No Sessions',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total > 0 ? (rate / 100).clamp(0.0, 1.0) : 0.0,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$attended / $total sessions attended',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        if (total > 0)
                          Text(
                            rate >= 75
                                ? (safeSkips > 0 ? 'Can miss $safeSkips' : 'On threshold')
                                : 'Attend $needed to reach 75%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection(List<dynamic> recentActivity) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, color: Color(0xFF007C91), size: 22),
              SizedBox(width: 10),
              Text(
                'Recent Attendance Records',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentActivity.length,
            separatorBuilder: (_, __) => const Divider(height: 16, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, idx) {
              final item = recentActivity[idx];
              final code = item['class_code'] ?? '';
              final name = item['class_name'] ?? '';
              final status = item['status'] ?? 'present';
              final date = item['marked_at'] ?? '';
              final isPresent = status == 'present';

              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPresent
                          ? const Color(0xFF10B981).withOpacity(0.12)
                          : const Color(0xFFEF4444).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPresent ? Icons.check_rounded : Icons.close_rounded,
                      color: isPresent ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$code - $name',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          date,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPresent ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isPresent ? 'Present' : 'Absent',
                      style: TextStyle(
                        color: isPresent ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
