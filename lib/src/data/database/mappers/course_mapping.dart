import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_attend/src/domain/models/course.dart';
import 'package:drift/drift.dart';

Course courseFromRow(CourseRow row) => Course(
  id: row.id,
  name: row.name,
  activeFrom: row.activeFrom == null
      ? null
      : localDateFromText(row.activeFrom!),
  activeUntil: row.activeUntil == null
      ? null
      : localDateFromText(row.activeUntil!),
);

CoursesCompanion courseToCompanion(Course course) => CoursesCompanion.insert(
  id: course.id,
  name: course.name,
  activeFrom: Value(
    course.activeFrom == null ? null : localDateToText(course.activeFrom!),
  ),
  activeUntil: Value(
    course.activeUntil == null ? null : localDateToText(course.activeUntil!),
  ),
);
