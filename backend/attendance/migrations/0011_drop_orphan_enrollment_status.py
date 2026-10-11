from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("attendance", "0010_remove_studentprofile_roll_no_and_more"),
    ]

    operations = [
        migrations.RunSQL(
            sql="SELECT 1;",
            reverse_sql="SELECT 1;",
        )
    ]
