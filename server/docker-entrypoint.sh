#!/bin/sh
set -e

# If BASE_URL is set, rewrite manifest.json so audio/lyrics/artwork URLs
# point at the host the phone will reach. Idempotent: existing absolute
# URLs are reset to __BASE_URL__ first, then substituted.
MANIFEST=/usr/share/nginx/html/manifest.json
if [ -n "${BASE_URL:-}" ] && [ -f "$MANIFEST" ]; then
  BASE="${BASE_URL%/}"
  sed -i -E "s#https?://[^/\"]+(/songs/|/lyrics/|/artwork/|/artists/)#__BASE_URL__\1#g" "$MANIFEST"
  sed -i "s#__BASE_URL__#${BASE}#g" "$MANIFEST"
  echo "music-server: rewrote manifest.json base URL -> ${BASE}"
fi

exec "$@"
