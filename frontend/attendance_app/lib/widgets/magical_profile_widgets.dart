import 'dart:ui';
import 'package:flutter/material.dart';

class MagicalBackground extends StatefulWidget {
  const MagicalBackground({super.key});

  @override
  State<MagicalBackground> createState() => _MagicalBackgroundState();
}

class _MagicalBackgroundState extends State<MagicalBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dark premium base
        Container(color: const Color(0xFF0F172A)),

        // Animated blobs
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              children: [
                Positioned(
                  top: -100 + (_controller.value * 50),
                  left: -100 - (_controller.value * 30),
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -150 - (_controller.value * 60),
                  right: -50 + (_controller.value * 40),
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF818CF8).withOpacity(0.15),
                    ),
                  ),
                ),
                Positioned(
                  top: 200 + (_controller.value * 40),
                  right: -100,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2DD4BF).withOpacity(0.1),
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // Blur overlay to create mesh effect
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ],
    );
  }
}

class MagicalGlassCard extends StatelessWidget {
  final String title;
  final String value;
  final Color accentColor;
  final double width;

  const MagicalGlassCard({
    super.key,
    required this.title,
    required this.value,
    required this.accentColor,
    this.width = 150,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: accentColor.withOpacity(0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MagicalAvatar extends StatefulWidget {
  final String initial;
  final double radius;

  const MagicalAvatar({
    super.key,
    required this.initial,
    this.radius = 60,
  });

  @override
  State<MagicalAvatar> createState() => _MagicalAvatarState();
}

class _MagicalAvatarState extends State<MagicalAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring
            Container(
              width: widget.radius * 2.5 + (_controller.value * 20),
              height: widget.radius * 2.5 + (_controller.value * 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF38BDF8).withOpacity(0.2 - (_controller.value * 0.1)),
                  width: 2,
                ),
              ),
            ),
            // Inner glow ring
            Container(
              width: widget.radius * 2.2 + (_controller.value * 10),
              height: widget.radius * 2.2 + (_controller.value * 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF818CF8).withOpacity(0.4 - (_controller.value * 0.2)),
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF818CF8).withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            // Avatar
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: widget.radius,
                backgroundColor: const Color(0xFF1E293B),
                child: Text(
                  widget.initial,
                  style: TextStyle(
                    fontSize: widget.radius * 0.8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
