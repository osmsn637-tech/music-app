#!/usr/bin/env bash
# Replaces __BASE_URL__ placeholders in content/manifest.json with the URL
# the Flutter app will reach the server at.
#
# Use this if you don't have Python installed (otherwise use generate_manifest.py
# which scans content/songs/ and rebuilds the manifest from scratch).
#
# Usage:
#   bash scripts/set_base_url.sh http://192.168.1.20:8000

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <base-url>"
  echo "example: $0 http://192.168.1.20:8000"
  exit 1
fi

BASE="${1%/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/../content/manifest.json"

if [ ! -f "$MANIFEST" ]; then
  echo "error: $MANIFEST not found"
  exit 1
fi

# Reset any existing absolute URL back to the placeholder, then substitute.
# This makes the script idempotent — safe to run twice with different URLs.
sed -i.bak -E "s#https?://[^/\"]+(/songs/|/lyrics/|/artwork/)#__BASE_URL__\1#g" "$MANIFEST"
sed -i "s#__BASE_URL__#$BASE#g" "$MANIFEST"
rm -f "$MANIFEST.bak"

echo "Wrote base URL $BASE into $MANIFEST"
