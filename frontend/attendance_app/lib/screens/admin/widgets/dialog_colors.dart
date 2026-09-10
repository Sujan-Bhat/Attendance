import 'package:flutter/material.dart';

/// Shared color palette for the admin add-student dialogs. Mirrors the
/// private `_AppColors` used by the Manage Students screen so the dialogs
/// stay visually consistent without reaching into file-private classes.
abstract class DialogColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);

  static const danger = Color(0xFFD32F2F);
  static const dangerBg = Color(0xFFFFEBEE);
}