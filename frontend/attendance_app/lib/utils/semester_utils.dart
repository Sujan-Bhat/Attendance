/// Numeric-aware ordering for semester labels so "Semester 2" sorts before
/// "Semester 10" (the server's lexicographic order gets this wrong).
///
/// Purely numeric labels compare numerically; anything non-numeric falls
/// back to string comparison, with numeric labels first.
int compareSemesters(String a, String b) {
  final ai = int.tryParse(a.trim());
  final bi = int.tryParse(b.trim());
  if (ai != null && bi != null) return ai.compareTo(bi);
  if (ai != null) return -1;
  if (bi != null) return 1;
  return a.compareTo(b);
}
