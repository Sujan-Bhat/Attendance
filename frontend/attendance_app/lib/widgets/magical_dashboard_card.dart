import 'package:flutter/material.dart';

class MagicalDashboardCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const MagicalDashboardCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  State<MagicalDashboardCard> createState() => _MagicalDashboardCardState();
}

class _MagicalDashboardCardState extends State<MagicalDashboardCard>
    with TickerProviderStateMixin {
  bool _hover = false;
  bool _pressed = false;

  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();

    // Pulse controller for icon (gentle breathing)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.95,
      upperBound: 1.08,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _pulseController.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _pulseController.forward();
        }
      });
    _pulseController.forward();

    // Shimmer controller
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _startShimmer() {
    _shimmerController.repeat();
  }

  void _stopShimmer() {
    _shimmerController.stop();
    _shimmerController.reset();
  }

  void _onTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.title} tapped'),
        duration: const Duration(milliseconds: 650),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double w = isMobile ? double.infinity : 260;
    final double h = isMobile ? 160 : 160;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        _startShimmer();
      },
      onExit: (_) {
        setState(() => _hover = false);
        _stopShimmer();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) {
          setState(() => _pressed = true);
          _startShimmer();
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          _stopShimmer();
          _onTap();
        },
        onTapCancel: () {
          setState(() => _pressed = false);
          _stopShimmer();
        },
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background card
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      widget.color.withOpacity((_hover || _pressed) ? 0.95 : 0.88),
                      Colors.white,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_hover || _pressed)
                          ? widget.color.withOpacity(0.36)
                          : Colors.black12,
                      blurRadius: (_hover || _pressed) ? 20 : 10,
                      spreadRadius: (_hover || _pressed) ? 2 : 0.5,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: (_hover || _pressed)
                        ? widget.color.withOpacity(0.9)
                        : Colors.white,
                    width: (_hover || _pressed) ? 1.6 : 0.8,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // Shimmer overlay
                      AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          final double t = _shimmerController.value;
                          final double dx =
                              (t * 2 - 1) * (MediaQuery.of(context).size.width);
                          return Transform.translate(
                            offset: Offset(dx * 0.02, 0),
                            child: Opacity(
                              opacity: (_hover || _pressed) ? 0.18 : 0.0,
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.9),
                                Colors.white.withOpacity(0.0),
                                Colors.white.withOpacity(0.0),
                              ],
                              begin: const Alignment(-1, -0.3),
                              end: const Alignment(1, 0.3),
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Inner content
                      Center(
                        child: Transform.translate(
                          offset: Offset(0, (_hover || _pressed) ? -6 : 0),
                          child: Transform.scale(
                            scale: (_hover || _pressed) ? 1.03 : 1.0,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18.0, vertical: 14),
                              child: Row(
                                children: [
                                  // Pulsing icon
                                  ScaleTransition(
                                    scale: _pulseController,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: widget.color.withOpacity(0.18),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Icon(
                                        widget.icon,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Titles
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          widget.title,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF111827),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          widget.subtitle,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[700],
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Soft outline glow
              if (_hover || _pressed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      opacity: 0.12,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withOpacity(0.35),
                              blurRadius: 40,
                              spreadRadius: 6,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}