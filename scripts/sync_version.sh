#!/usr/bin/env bash
# Reads the version from pubspec.yaml and writes it into lib/app_version.dart.
# Run automatically by Makefile build targets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

VERSION=$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/version: \([^+]*\).*/\1/')

cat > "$ROOT/lib/app_version.dart" <<EOF
// App version constant — auto-generated from pubspec.yaml by scripts/sync_version.sh.
// Do not edit by hand; run 'make sync-version' or any build target instead.
const kAppVersion = '$VERSION';
EOF

echo "app_version.dart updated to $VERSION"
