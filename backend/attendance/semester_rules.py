"""Single-semester rule for students.

A student belongs to exactly one semester. Their semester is their
StudentProfile.semester when set, otherwise the (single) semester of their
enrolled classes. Every enrollment-creation point must reject adding a student
to a class from a different semester.
"""

from .models import Enrollment, StudentProfile


def student_current_semester(student):
    """Return the student's single semester, or None if they have none.

    Preference order: profile semester, then the semester of their enrolled
    classes (only meaningful when all classes share one semester).
    """
    try:
        profile = StudentProfile.objects.get(student=student)
    except StudentProfile.DoesNotExist:
        profile = None

    profile_sem = None
    if profile and profile.semester:
        profile_sem = profile.semester.strip()

    if profile_sem:
        return profile_sem

    enrolled_sems = set(
        Enrollment.objects.filter(student=student)
        .values_list('class_obj__semester', flat=True)
    )
    enrolled_sems = {s for s in enrolled_sems if s}

    if len(enrolled_sems) == 1:
        return enrolled_sems.pop()
    return None


def enforce_single_semester(student, class_obj):
    """Return an error message if enrolling `student` in `class_obj` would
    put them in more than one semester, otherwise None."""
    target_sem = (class_obj.semester or '').strip()

    try:
        profile = StudentProfile.objects.get(student=student)
    except StudentProfile.DoesNotExist:
        profile = None

    profile_sem = None
    if profile and profile.semester:
        profile_sem = profile.semester.strip()

    enrolled_sems = set(
        Enrollment.objects.filter(student=student)
        .values_list('class_obj__semester', flat=True)
    )
    enrolled_sems = {s for s in enrolled_sems if s}

    if profile_sem:
        if profile_sem != target_sem:
            return (
                f'Student is already in Semester {profile_sem}. '
                f'A student can only belong to one semester '
                f'(requested {target_sem}).'
            )
        if enrolled_sems and any(s != profile_sem for s in enrolled_sems):
            return (
                f'Student has enrollments in multiple semesters '
                f'({", ".join(sorted(enrolled_sems))}). '
                f'Fix the student\'s data before enrolling them.'
            )
        return None

    if len(enrolled_sems) == 1:
        current = enrolled_sems.pop()
        if current != target_sem:
            return (
                f'Student is already in Semester {current}. '
                f'A student can only belong to one semester '
                f'(requested {target_sem}).'
            )
        return None

    if len(enrolled_sems) > 1:
        return (
            f'Student is enrolled in multiple semesters '
            f'({", ".join(sorted(enrolled_sems))}). '
            f'Fix the student\'s data before enrolling them.'
        )

    return None


def set_student_semester(student, semester):
    """Assign `semester` to the student's profile (creating it if needed)."""
    semester = (semester or '').strip()
    if not semester:
        return
    profile, _ = StudentProfile.objects.get_or_create(student=student)
    if profile.semester != semester:
        profile.semester = semester
        profile.save(update_fields=['semester'])