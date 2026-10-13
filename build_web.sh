#!/usr/bin/env bash
set -euo pipefail

# Build the Flutter web app and sync the output into backend/flutter_web/,
# which the Django server serves from.
#
# Run this after finishing frontend feature work so that the app served at
# http://localhost:8000 (and by the deployed backend) reflects your changes:
#
#   ./build_web.sh

cd frontend/attendance_app

echo "Fetching Flutter dependencies..."
flutter pub get

echo "Building Flutter web app (release)..."
flutter build web --release

echo "Syncing build output into backend/flutter_web/..."
rm -rf ../../backend/flutter_web/*
cp -r build/web/* ../../backend/flutter_web/

echo "Done. Flutter web build synced into backend/flutter_web/"
