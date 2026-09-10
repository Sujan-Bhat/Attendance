import 'package:flutter/material.dart';

/// Hover-lifting admin card shared by the dashboard and manage screens.
///
/// Matches the teacher dashboard's animation: lift + scale on hover, a soft
/// glow shadow in the card's accent color, and the leading icon gives a small
/// elastic rotation.
class AdminAnimatedCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool compact;

  const AdminAnimatedCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.gradient,
    required this.onTap,
    this.trailing,
    this.compact = false,
  });

  @override
  State<AdminAnimatedCard> createState() => _AdminAnimatedCardState();
}

class _AdminAnimatedCardState extends State<AdminAnimatedCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _translateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _translateAnimation = Tween<double>(
      begin: 0.0,
      end: -8.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.compact;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTap: widget.onTap,
child: AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    final iconCircle = Container(
                      width: isCompact ? 52 : 68,
                      height: isCompact ? 52 : 68,
                      padding: EdgeInsets.all(isCompact ? 10 : 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        border: Border.all(
                          color: widget.color.withValues(alpha: 0.70),
                          width: 1.5,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Transform.rotate(
                        angle: _rotationAnimation.value,
                        child: Icon(
                          widget.icon,
                          color: widget.color,
                          size: isCompact ? 24 : 30,
                        ),
                      ),
                    );

                    final textColumn = Column(
                      crossAxisAlignment: isCompact
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: isCompact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: isCompact ? TextAlign.center : null,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: isCompact ? 16 : 20,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: isCompact ? 4 : 6),
                        Text(
                          widget.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: isCompact ? TextAlign.center : null,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: isCompact ? 12 : 14,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    );

                    final Widget inner = isCompact
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              iconCircle,
                              const SizedBox(height: 12),
                              textColumn,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              iconCircle,
                              const SizedBox(width: 16),
                              Expanded(child: textColumn),
                              if (widget.trailing != null) ...[
                                const SizedBox(width: 8),
                                widget.trailing!,
                              ],
                            ],
                          );

                    return Transform.translate(
                      offset: Offset(0, _translateAnimation.value),
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 16 : 32,
                            vertical: isCompact ? 16 : 24,
                          ),
                          decoration: ShapeDecoration(
                            gradient: LinearGradient(
                              begin: const Alignment(-0.05, -0.07),
                              end: const Alignment(1.18, 1.28),
                              colors: widget.gradient,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(isCompact ? 16 : 43),
                              side: const BorderSide(
                                color: Color(0xFFE5E7EB),
                                width: 1.5,
                              ),
                            ),
                            shadows: [
                              BoxShadow(
                                color: widget.color.withValues(
                                  alpha: _isHovered ? 0.6 : 0.1,
                                ),
                                blurRadius: _isHovered ? 25 : 10,
                                spreadRadius: _isHovered ? 2 : 0,
                                offset: Offset(0, _isHovered ? 12 : 4),
                              ),
                            ],
                          ),
                          child: inner,
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
