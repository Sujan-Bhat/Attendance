import 'package:flutter/material.dart';

abstract class ProfileColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const background = Color(0xFFF7F9FC);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class ProfileAvatar extends StatefulWidget {
  final String initial;
  final double radius;

  const ProfileAvatar({super.key, required this.initial, this.radius = 60});

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ProfileColors.teal.withOpacity(0.12 + t * 0.08),
                blurRadius: 24 + t * 8,
                spreadRadius: 2 + t * 2,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  ProfileColors.teal.withOpacity(0.35 - t * 0.15),
                  ProfileColors.tealDark.withOpacity(0.25 - t * 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CircleAvatar(
              radius: widget.radius,
              backgroundColor: Colors.white,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [ProfileColors.tealDark, ProfileColors.teal],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.initial,
                    style: TextStyle(
                      fontSize: widget.radius * 0.8,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProfileStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;

  const ProfileStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.13, 0),
          end: const Alignment(1.12, 1),
          colors: [accentColor.withOpacity(0.18), Colors.white],
        ),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 30,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: ProfileColors.textMuted,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  const ProfileInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accentColor = ProfileColors.teal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ProfileColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: ProfileColors.textMuted,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: ProfileColors.textPrimary,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  const ProfileActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: filled ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: filled ? color : color.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: filled ? Colors.white : color, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool compact;

  const ProfileSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: compact ? 20 : 26,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: compact ? 4 : 12,
              height: compact ? 24 : 43,
              decoration: ShapeDecoration(
                color: ProfileColors.teal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(compact ? 2 : 6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: compact ? 18 : 33,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfileRolePill extends StatelessWidget {
  final String role;
  final Color color;

  const ProfileRolePill({super.key, required this.role, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
