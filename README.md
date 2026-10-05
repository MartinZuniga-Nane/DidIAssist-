# DidIAssist

A local-first mobile app that automatically records your class attendance.

Set your campus location and your class schedule. When class time comes, the app checks whether you are on campus and records your attendance. All location data stays on your device.

> Status: the core (attendance engine, storage, geofencing, background work and notifications) is implemented. The user interface is in progress.

## Features

- **Automatic attendance**: OS geofences around your campus record when you arrive. Each class is marked present, late or absent based on a configurable window (by default it opens 15 minutes early and gives 10 minutes of grace).
- **Manual overrides**: you can mark a class manually, including excused absences. Automatic evaluation never overwrites them.
- **Travel time from home**: estimates when you will arrive and whether you are running late. It starts with an offline estimate per travel mode and learns your real commute time from past trips.
- **Reminders**: departure reminders before class and notifications when attendance is recorded, in English and Spanish.
- **Private by design**: no accounts, no server, no API keys. Everything is stored in a local SQLite database.

## Tech stack

- Flutter 3.32 / Dart 3.8 (Android and iOS)
- [drift](https://pub.dev/packages/drift) for local storage, shared across isolates
- [native_geofence](https://pub.dev/packages/native_geofence) and [geolocator](https://pub.dev/packages/geolocator) for location
- [workmanager](https://pub.dev/packages/workmanager) for periodic background evaluation
- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) and gen-l10n

## Getting started

Requires Flutter 3.32.4. Generated code is not committed, so generate it after fetching dependencies:

```sh
flutter pub get
flutter gen-l10n
dart run drift_dev schema steps drift_schemas/app_database lib/src/data/database/app_database.steps.dart
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema generate drift_schemas/app_database test/src/data/database/migrations/app_database/generated
flutter run
```

## Testing

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Database tests run on the host and need a native SQLite library: `libsqlite3-dev` on Linux, or `sqlite3.dll` on your `PATH` on Windows.

## Project structure

```
lib/src/
  core/      pure helpers (geo math, local dates and times)
  domain/    models, repository interfaces and business services (pure Dart)
  data/      drift database, mappers and repository implementations
  platform/  plugin adapters (geofencing, location, notifications, background work)
  app/       composition root and background pipeline
  l10n/      English and Spanish translations
```

## Permissions

- **Location (always)**: lets geofences record your arrival while the app is closed.
- **Notifications**: departure reminders and attendance results.

Location data never leaves the device.
