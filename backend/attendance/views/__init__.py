"""View modules for the attendance app.

Every public view is re-exported here so that
`from attendance.views import X` keeps working after the split into
focused modules.
"""

from .auth_views import (  # noqa: F401
    RegisterView,
    MeView,
    MyTokenObtainPairSerializer,
    MyTokenObtainPairView,
    ping,
)

from .classes_views import (  # noqa: F401
    class_list_create,
    class_detail,
    get_class_students,
    add_student_to_class,
    remove_student_from_class,
    update_student_in_class,
    join_class_by_code,
)

from .sessions_views import (  # noqa: F401
    create_session,
    get_active_sessions,
    get_student_active_sessions,
    get_session_details,
    calculate_totp_and_captcha,
    mark_attendance,
    sync_offline_session,
    end_session,
    cancel_session,
    mark_all_present_session,
    edit_session,
    update_session_attendance,
)

from .verification_views import (  # noqa: F401
    upload_reference_image,
    verify_image,
    sync_offline_pattern,
    register_face,
    verify_face_auth,
)

from .history_views import (  # noqa: F401
    get_student_enrolled_classes,
    get_student_attendance_history,
    check_student_by_email,
    get_teacher_attendance_history,
    update_attendance_status,
    manual_mark_attendance,
    get_session_attendance_details,
)

from .announcements_views import (  # noqa: F401
    announcements_list_create,
    announcement_detail,
)

from .misc_views import (  # noqa: F401
    assetlinks_json,
)

__all__ = [
    "RegisterView",
    "MeView",
    "MyTokenObtainPairSerializer",
    "MyTokenObtainPairView",
    "ping",
    "class_list_create",
    "class_detail",
    "get_class_students",
    "add_student_to_class",
    "remove_student_from_class",
    "update_student_in_class",
    "join_class_by_code",
    "create_session",
    "get_active_sessions",
    "get_student_active_sessions",
    "get_session_details",
    "calculate_totp_and_captcha",
    "mark_attendance",
    "sync_offline_session",
    "end_session",
    "cancel_session",
    "mark_all_present_session",
    "edit_session",
    "update_session_attendance",
    "upload_reference_image",
    "verify_image",
    "sync_offline_pattern",
    "register_face",
    "verify_face_auth",
    "get_student_enrolled_classes",
    "get_student_attendance_history",
    "check_student_by_email",
    "get_teacher_attendance_history",
    "update_attendance_status",
    "manual_mark_attendance",
    "get_session_attendance_details",
    "announcements_list_create",
    "announcement_detail",
    "assetlinks_json",
]
