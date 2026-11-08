import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../widgets/teacher_web_layout.dart';

class TeacherAnalyticsScreen extends StatefulWidget {
  const TeacherAnalyticsScreen({super.key});

  @override
  State<TeacherAnalyticsScreen> createState() => _TeacherAnalyticsScreenState();
}

class _TeacherAnalyticsScreenState extends State<TeacherAnalyticsScreen> {
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
      final res = await _analyticsService.getTeacherAnalytics();
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

  Color _getStatusColor(double rate) {
    if (rate >= 75.0) return const Color(0xFF10B981); // Emerald Green
    if (rate >= 65.0) return const Color(0xFFF59E0B); // Amber
    return const Color(0xFFEF4444); // Red
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    return TeacherWebLayout(
      currentRoute: 'Analytics',
      mobileChild: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'Attendance Analytics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          elevation: 0.5,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchAnalytics,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _fetchAnalytics,
          child: body,
        ),
      ),
      desktopBody: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'Attendance Analytics & Insights',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          elevation: 0.5,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Analytics',
              onPressed: _fetchAnalytics,
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: body,
      ),
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
    final atRiskList = (_data?['at_risk_students'] as List<dynamic>? ?? []);
    final weeklyTrend = (_data?['weekly_trend'] as List<dynamic>? ?? []);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _buildOverviewCards(overview),
        const SizedBox(height: 24),
        if (weeklyTrend.isNotEmpty) ...[
          _buildWeeklyTrendSection(weeklyTrend),
          const SizedBox(height: 24),
        ],
        _buildClassBreakdownSection(classesList),
        const SizedBox(height: 24),
        _buildAtRiskStudentsSection(atRiskList),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildOverviewCards(Map<String, dynamic> overview) {
    final overallRate = (overview['overall_rate'] as num?)?.toDouble() ?? 0.0;
    final totalClasses = overview['total_classes'] ?? 0;
    final totalSessions = overview['total_sessions'] ?? 0;
    final totalStudents = overview['total_students'] ?? 0;
    final atRiskCount = overview['at_risk_count'] ?? 0;
    final presentCount = overview['present_count'] ?? 0;
    final absentCount = overview['absent_count'] ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Column(
          children: [
            // Top Primary Banner Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007C91).withOpacity(0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: CircularProgressIndicator(
                          value: (overallRate / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 8,
                        ),
                      ),
                      Text(
                        '${overallRate.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                          'Overall Class Attendance',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          overallRate >= 75
                              ? 'Healthy Attendance Rate'
                              : 'Attention Required (< 75%)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$presentCount Present • $absentCount Absent across all sessions',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Metric Cards Grid
            GridView.count(
              crossAxisCount: isWide ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: isWide ? 1.6 : 1.35,
              children: [
                _buildMetricCard(
                  title: 'Total Classes',
                  value: '$totalClasses',
                  icon: Icons.class_rounded,
                  color: const Color(0xFF3B82F6),
                ),
                _buildMetricCard(
                  title: 'Total Sessions',
                  value: '$totalSessions',
                  icon: Icons.timer_rounded,
                  color: const Color(0xFF10B981),
                ),
                _buildMetricCard(
                  title: 'Enrolled Students',
                  value: '$totalStudents',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF8B5CF6),
                ),
                _buildMetricCard(
                  title: 'At-Risk Students',
                  value: '$atRiskCount',
                  icon: Icons.warning_amber_rounded,
                  color: atRiskCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTrendSection(List<dynamic> trend) {
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
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: Color(0xFF007C91), size: 22),
              const SizedBox(width: 10),
              const Text(
                '7-Day Attendance Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.map((dayData) {
                final rate = (dayData['rate'] as num?)?.toDouble() ?? 0.0;
                final dayName = dayData['day'] as String? ?? '';
                final total = dayData['total'] ?? 0;
                final barHeight = (rate / 100 * 70).clamp(4.0, 70.0);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      total > 0 ? '${rate.toStringAsFixed(0)}%' : '-',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: total > 0 ? const Color(0xFF007C91) : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 28,
                      height: barHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: total > 0
                              ? [const Color(0xFF007C91), const Color(0xFF0097A7)]
                              : [const Color(0xFFE2E8F0), const Color(0xFFE2E8F0)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassBreakdownSection(List<dynamic> classesList) {
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
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: Color(0xFF007C91), size: 22),
              const SizedBox(width: 10),
              const Text(
                'Class Breakdown & Performance',
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
                'No classes created yet.',
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
                final rate = (c['attendance_rate'] as num?)?.toDouble() ?? 0.0;
                final totalSessions = c['total_sessions'] ?? 0;
                final enrolled = c['enrolled_students'] ?? 0;
                final color = _getStatusColor(rate);

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
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF1E293B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${rate.toStringAsFixed(1)}%',
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
                        value: (rate / 100).clamp(0.0, 1.0),
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$enrolled enrolled • $totalSessions sessions held',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        Text(
                          rate >= 75 ? 'Good Standing' : 'Low Attendance Alert',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
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

  Widget _buildAtRiskStudentsSection(List<dynamic> atRiskList) {
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
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
              const SizedBox(width: 10),
              const Text(
                'At-Risk Students (< 75% Attendance)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (atRiskList.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${atRiskList.length} Defaulters',
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (atRiskList.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Great job! All students are currently above the 75% attendance threshold.',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: atRiskList.length,
              separatorBuilder: (_, __) => const Divider(height: 16, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, idx) {
                final student = atRiskList[idx];
                final name = student['name'] ?? '';
                final email = student['email'] ?? '';
                final classCode = student['class_code'] ?? '';
                final attended = student['attended'] ?? 0;
                final total = student['total_sessions'] ?? 0;
                final rate = (student['attendance_rate'] as num?)?.toDouble() ?? 0.0;

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFFEE2E2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'S',
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                          ),
                          Text(
                            '$email • $classCode ($attended/$total sessions)',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${rate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
