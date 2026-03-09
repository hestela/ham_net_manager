# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`ham_net_manager` is a Flutter application for managing ham radio nets. It targets **desktop only**: Linux, macOS, and Windows.

**Key dependency:** `sqflite_common_ffi` — SQLite database access for desktop/FFI platforms.

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app (specify device with -d: android, ios, macos, windows, linux, chrome)
flutter run

# Build
flutter build apk          # Android
flutter build macos        # macOS
flutter build windows      # Windows
flutter build linux        # Linux (GTK)

# Linux AppImage (portable executable for distribution)
./scripts/build_appimage.sh

# Analyze (lint)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/path/to/file_test.dart
```

## Architecture

Desktop-only Flutter app (Linux/Windows/macOS). SQLite via `sqflite_common_ffi` — `databaseFactoryFfi` is set globally in `main()` before `runApp`.

**Database** (`lib/database/database_helper.dart`): singleton, handles open/create, schema migrations. DB files live in `~/Documents/ham_net_manager/<city-slug>-weekly-net.sqlite`. Schema version is currently **2**.

**Models** (`lib/models/`): plain Dart classes with `fromMap` constructors.

**Repository** (`lib/repositories/net_repository.dart`): all SQL for the main screen — persons, weeks, checkins, checkin_methods, net_roles. Constants `kCheckInMethods` and `kHamOnlyMethods` define valid methods and which ones count toward the ham-only unique total.

**Screens**:
- `setup_screen.dart` — first-run city name input / existing DB picker
- `weekly_checkin_screen.dart` — main weekly check-in table (the primary UI)

**Check-in logic**:
- "Checked in" column = person has ≥1 method checked for the week
- Ham-only unique count = members with ≥1 non-GMRS method (`kHamOnlyMethods`)
- Including-GMRS count = members with any check-in

**Net roles** are stored per `week_id` + `day_of_week` (`Sunday`/`Monday`/`Tuesday`/`Other`) + `role` (`net_control`/`scribe`). The `display_name` column handles free-text for the "Other" column.
