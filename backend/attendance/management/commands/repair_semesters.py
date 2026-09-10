"""One-off data repair to enforce a single semester per student.

- Students enrolled in classes across more than one semester have the
  extra-semester enrollments removed. The primary semester is the student's
  profile semester (when it matches one of their enrolled semesters),
  otherwise the semester with the most enrollments (ties break by the
  earliest enrollment).
- Every enrolled student's profile semester is backfilled from their (now
  single) class semester so all students carry an explicit semester.

Prints an audit log of every change. Safe to re-run; it is idempotent.
"""

from collections import defaultdict

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

from attendance.models import Enrollment, StudentProfile


class Command(BaseCommand):
    help = 'Enforce a single semester per student (repair + backfill).'

    def handle(self, *args, **options):
        User = get_user_model()
        students = User.objects.filter(role='student').order_by('id')

        # Map student -> profile semester (may be None/empty).
        profile_semester = {}
        for p in StudentProfile.objects.filter(student__role='student').select_related('student'):
            sem = (p.semester or '').strip()
            profile_semester[p.student_id] = sem or None

        # Map student -> list of (semester, enrolled_at date).
        enrollments = defaultdict(list)
        for e in Enrollment.objects.select_related('class_obj', 'student'):
            enrollments[e.student_id].append(
                (e.class_obj.semester, e.enrolled_at, e)
            )

        repairCount = 0
        backfillCount = 0
        removeCount = 0

        for student in students:
            rows = enrollments.get(student.id, [])
            if not rows:
                continue

            sems = {sem for sem, _, _ in rows if sem}
            if not sems:
                continue

            profile_sem = profile_semester.get(student.id)

            if len(sems) > 1:
                # Choose the primary semester.
                primary = None
                if profile_sem and profile_sem in sems:
                    primary = profile_sem
                if primary is None:
                    counts = defaultdict(int)
                    earliest = {}
                    for sem, enrolled_at, _ in rows:
                        counts[sem] += 1
                        earliest[sem] = min(
                            earliest.get(sem, enrolled_at), enrolled_at
                        )
                    primary = sorted(
                        counts, key=lambda s: (-counts[s], earliest[s])
                    )[0]

                removed = []
                for sem, _, enrollment in rows:
                    if sem != primary:
                        removed.append((sem, enrollment.class_obj.class_code))
                        enrollment.delete()
                        removeCount += 1

                self.set_profile(student.id, primary)
                repairCount += 1
                self.stdout.write(
                    f'REPAIR student #{student.id} ({student.username}): '
                    f'primary semester={primary!r}, removed='
                    f'{removed}'
                )

            elif len(sems) == 1:
                single = sems.pop()
                if profile_sem != single:
                    self.set_profile(student.id, single)
                    backfillCount += 1
                    self.stdout.write(
                        f'BACKFILL student #{student.id} '
                        f'({student.username}): semester={single!r}'
                    )

        self.stdout.write(self.style.SUCCESS(
            f'Done. repaired={repairCount}, backfilled={backfillCount}, '
            f'enrollments_removed={removeCount}'
        ))

    def set_profile(self, student_id, semester):
        profile, _ = StudentProfile.objects.get_or_create(student_id=student_id)
        if profile.semester != semester:
            profile.semester = semester
            profile.save(update_fields=['semester'])