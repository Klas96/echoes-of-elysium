#!/usr/bin/env bash
# Copy Echoes details-page marketing assets into a portfolio-website checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/docs/brand/portfolio"
DEST="${1:-}"
if [[ -z "$DEST" || ! -d "$DEST" ]]; then
  echo "Usage: $0 /path/to/portfolio-website" >&2
  exit 2
fi
install -D -m 0644 "$SRC/echoes-of-elysium-feature.jpg" "$DEST/static/images/portfolio/echoes-of-elysium-feature.jpg"
install -D -m 0644 "$SRC/echoes-of-elysium.png" "$DEST/static/images/portfolio/echoes-of-elysium.png"
install -D -m 0644 "$SRC/echoes-of-elysium-screenshot.jpg" "$DEST/static/images/portfolio/echoes-of-elysium-screenshot.jpg"
install -D -m 0644 "$SRC/echoes-of-elysium-og.jpg" "$DEST/static/images/og/echoes-of-elysium.jpg"
install -D -m 0644 "$SRC/echoes-of-elysium-og.png" "$DEST/static/images/portfolio/echoes-of-elysium-og.png"
echo "Synced Echoes portfolio assets into $DEST"
git -C "$DEST" status --short -- static/images/portfolio/echoes-of-elysium* static/images/og/echoes-of-elysium.jpg || true
