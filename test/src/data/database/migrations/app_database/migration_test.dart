import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_database.dart';
import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUp(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('fresh database matches the exported schema version', () async {
    final database = createTestDatabase();
    addTearDown(database.close);
    expect(GeneratedHelper.versions.last, database.schemaVersion);
    await verifier.migrateAndValidate(database, database.schemaVersion);
  });

  for (final (index, from) in GeneratedHelper.versions.indexed) {
    for (final to in GeneratedHelper.versions.skip(index)) {
      test('schema $from opens and migrates to $to', () async {
        final schema = await verifier.schemaAt(from);
        addTearDown(schema.rawDatabase.dispose);
        final database = AppDatabase.forTesting(schema.newConnection());
        addTearDown(database.close);
        await verifier.migrateAndValidate(database, to);
        expect(
          (await database.customSelect('PRAGMA foreign_keys').getSingle())
              .read<int>('foreign_keys'),
          1,
        );
      });
    }
  }
}
