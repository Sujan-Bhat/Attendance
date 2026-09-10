"""Admin bulk student creation from an Excel upload (and re-validation by rows).

Three endpoints follow the contract consumed by the Flutter web client
(see frontend `bulk_students_service.dart`):

  POST /api/v1/admin/students/bulk/validate/
      multipart: file (.xlsx), default_password
  POST /api/v1/admin/students/bulk/validate-rows/
      json: {rows: [{name, email, semester}], default_password}
  POST /api/v1/admin/students/bulk/create/
      json: {rows: [{name, email, semester}], default_password}

Validation is *non-destructive*: it never creates rows. Creation is
all-or-nothing inside a single transaction.
"""

from io import BytesIO

import openpyxl
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from .models import StudentProfile

User = get_user_model()

EXPECTED_COLUMNS = {'name', 'email', 'semester'}
MAX_ROWS = 500
DEFAULT_PASSWORD_MIN_LENGTH = 6


def _require_admin(request):
    """Return an error Response if the user is not an admin, else None."""
    if request.user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN,
        )
    return None


def _normalize_rows(rows):
    """Lowercase/trim email, trim name and semester in place; return as dicts."""
    normalized = []
    for row in rows:
        normalized.append({
            'name': (row.get('name') or '').strip(),
            'email': (row.get('email') or '').strip().lower(),
            'semester': (row.get('semester') or '').strip(),
        })
    return normalized


def _validate_rows(rows, default_password):
    """Return row error maps keyed by field + a batch-level error.

    rows items must already be normalized dicts (name/email/semester).
    Returns (errors_by_row, batch_error) where errors_by_row is a list of
    {field: message} dicts aligned with `rows`.
    """
    batch_error = None
    if not default_password or len(default_password) < DEFAULT_PASSWORD_MIN_LENGTH:
        batch_error = 'Default password must be at least 6 characters'

    seen_emails = set()
    duplicate_emails = set()
    for row in rows:
        email = row['email']
        if email:
            if email in seen_emails:
                duplicate_emails.add(email)
            seen_emails.add(email)

    errors_by_row = []
    for index, row in enumerate(rows):
        errors = {}
        name = row['name']
        email = row['email']
        semester = row['semester']

        if not name:
            errors['name'] = 'Name is required'
        elif User.objects.filter(username=name).exists():
            errors['name'] = 'Name already in use'

        if not email:
            errors['email'] = 'Email is required'
        elif '@' not in email or '.' not in email:
            errors['email'] = 'Enter a valid email'
        elif email in duplicate_emails:
            errors['email'] = 'Email appears more than once in the file'
        elif User.objects.filter(email=email).exists():
            errors['email'] = 'Email already in use'

        if not semester:
            errors['semester'] = 'Semester is required'

        errors_by_row.append(errors)

    return errors_by_row, batch_error


def _build_response(rows, errors_by_row, batch_error, row_numbers=None):
    """Shape the response exactly as the Flutter client parses it."""
    if row_numbers is None:
        row_numbers = list(range(2, 2 + len(rows)))
    payload_rows = []
    for row, errors, row_number in zip(rows, errors_by_row, row_numbers):
        payload_rows.append({
            'row': row_number,
            'name': row['name'],
            'email': row['email'],
            'semester': row['semester'],
            'errors': errors,
        })
    valid = not batch_error and all(not e for e in errors_by_row)
    return Response({
        'valid': valid,
        'total': len(rows),
        'rows': payload_rows,
        'error': batch_error,
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def admin_bulk_validate_students(request):
    """Parse an uploaded .xlsx and validate every row (no writes)."""
    denied = _require_admin(request)
    if denied:
        return denied

    file_obj = request.FILES.get('file')
    if not file_obj:
        return Response(
            {'error': 'No file was uploaded'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if not file_obj.name.lower().endswith('.xlsx'):
        return Response(
            {'error': 'Only .xlsx files are supported. Download the template from the Add Students dialog'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        workbook = openpyxl.load_workbook(BytesIO(file_obj.read()), read_only=True, data_only=True)
    except Exception:
        return Response(
            {'error': 'Could not read that file. Make sure it is a valid .xlsx workbook'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    sheet = workbook.active
    if sheet.max_row is None or sheet.max_row < 2:
        return Response(
            {'error': 'The file has no student rows'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # Header row: first non-empty row, case-insensitive name/email/semester.
    header = None
    header_index = 0
    for row_index, row in enumerate(sheet.iter_rows(values_only=True), start=1):
        if any(cell is not None and str(cell).strip() for cell in row):
            header = {
                (str(cell) if cell is not None else '').strip().lower(): col
                for col, cell in enumerate(row)
            }
            header_index = row_index
            break
    if header is None or not {'name', 'email', 'semester'}.issubset(header.keys()):
        return Response(
            {'error': 'Template must have Name, Email, and Semester columns'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    name_col = header['name']
    email_col = header['email']
    semester_col = header['semester']

    raw_rows = []
    for row_index, row in enumerate(sheet.iter_rows(min_row=header_index + 1, values_only=True), start=header_index + 1):
        if len(raw_rows) >= MAX_ROWS:
            return Response(
                {'error': f'Too many rows. Maximum is {MAX_ROWS}'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        width = len(row)
        name = str(row[name_col]).strip() if name_col < width and row[name_col] is not None else ''
        email = str(row[email_col]).strip() if email_col < width and row[email_col] is not None else ''
        semester = str(row[semester_col]).strip() if semester_col < width and row[semester_col] is not None else ''
        if not name and not email and not semester:
            continue  # skip blank rows
        raw_rows.append({
            'name': name,
            'email': email.lower(),
            'semester': semester,
            '_row_number': row_index,
        })

    if not raw_rows:
        return Response(
            {'error': 'The file has no student rows'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    default_password = request.data.get('default_password', '')
    rows = [
        {'name': r['name'], 'email': r['email'], 'semester': r['semester']}
        for r in raw_rows
    ]
    errors_by_row, batch_error = _validate_rows(rows, default_password)
    row_numbers = [r['_row_number'] for r in raw_rows]
    return _build_response(rows, errors_by_row, batch_error, row_numbers=row_numbers)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def admin_bulk_validate_rows(request):
    """Re-validate (possibly edited) rows without touching the DB."""
    denied = _require_admin(request)
    if denied:
        return denied

    data = request.data or {}
    raw_rows = data.get('rows') or []
    default_password = data.get('default_password') or ''

    if not isinstance(raw_rows, list):
        return Response(
            {'error': 'rows must be a list'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if len(raw_rows) > MAX_ROWS:
        return Response(
            {'error': f'Too many rows. Maximum is {MAX_ROWS}'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    rows = _normalize_rows(raw_rows)
    errors_by_row, batch_error = _validate_rows(rows, default_password)
    return _build_response(rows, errors_by_row, batch_error)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def admin_bulk_create_students(request):
    """Create every row atomically (all-or-nothing)."""
    denied = _require_admin(request)
    if denied:
        return denied

    data = request.data or {}
    raw_rows = data.get('rows') or []
    default_password = data.get('default_password') or ''

    if not isinstance(raw_rows, list):
        return Response(
            {'error': 'rows must be a list'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if not raw_rows:
        return Response(
            {'error': 'No students to create'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if len(raw_rows) > MAX_ROWS:
        return Response(
            {'error': f'Too many rows. Maximum is {MAX_ROWS}'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    rows = _normalize_rows(raw_rows)

    # Final gate: reject cleanly when validation is still failing.
    errors_by_row, batch_error = _validate_rows(rows, default_password)
    if batch_error or any(e for e in errors_by_row):
        return Response(
            {'error': 'Fix the errors in the table first'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    created_users = []
    try:
        with transaction.atomic():
            for row in rows:
                new_user = User(
                    username=row['name'],
                    email=row['email'],
                    role='student',
                )
                new_user.set_password(default_password)
                new_user.save()
                student_profile = StudentProfile.objects.create(student=new_user)
                if row['semester']:
                    student_profile.semester = row['semester']
                    student_profile.save(update_fields=['semester'])
                created_users.append({
                    'id': new_user.id,
                    'username': new_user.username,
                    'email': new_user.email,
                    'semester': row['semester'],
                })
    except IntegrityError:
        transaction.set_rollback(True)
        return Response(
            {'error': 'Some emails or usernames were taken just now. Re-validate and try again'},
            status=status.HTTP_409_CONFLICT,
        )

    return Response({
        'success': True,
        'created': len(created_users),
        'users': created_users,
    }, status=status.HTTP_201_CREATED)