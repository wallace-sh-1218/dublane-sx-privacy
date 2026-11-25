#!/usr/bin/env bash
#
# Build the static site for Cloudflare Pages.
#
# GitHub Pages serves this repository under /dublane-sx-privacy/, while
# Cloudflare Pages serves the same files from the domain root. The only
# differences are the origin inside hreflang/canonical links and the one
# root-absolute path in the privacy stub, so the build copies the published
# files and rewrites those two things.
#
# Usage:
#   scripts/build-cloudflare.sh
#   SITE_ORIGIN=example.com scripts/build-cloudflare.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
ORIGIN="${SITE_ORIGIN:-dublane.pages.dev}"
SOURCE_HOST="wallace-sh-1218.github.io"
SOURCE_PATH="/dublane-sx-privacy/"

die() { echo "build: $*" >&2; exit 1; }

[ -f "$ROOT/index.html" ] || die "index.html not found in $ROOT"
[ -f "$ROOT/deploy/_headers" ] || die "deploy/_headers is missing"
[ -f "$ROOT/deploy/_redirects" ] || die "deploy/_redirects is missing"

rm -rf "$DIST"
mkdir -p "$DIST"

# Only published files: no scripts/, no deploy/, no git data.
cp "$ROOT/index.html" "$ROOT/privacy-policy.html" "$DIST/"
cp -R "$ROOT/help" "$DIST/help"
cp "$ROOT/deploy/_headers" "$ROOT/deploy/_redirects" "$DIST/"

# Absolute URLs follow the deployment origin. Written with a temporary file so
# the same script runs on macOS (BSD sed) and on the Linux build image.
rewritten=0
while IFS= read -r -d '' file; do
  sed "s|https://${SOURCE_HOST}/dublane-sx-privacy|https://${ORIGIN}|g" "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
  rewritten=$((rewritten + 1))
done < <(find "$DIST" -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' \) -print0)

# The privacy stub points at the site root here, not at the repository path.
sed "s|${SOURCE_PATH}|/|g" "$DIST/privacy-policy.html" > "$DIST/privacy-policy.html.tmp"
mv "$DIST/privacy-policy.html.tmp" "$DIST/privacy-policy.html"

if grep -rlq "$SOURCE_HOST" "$DIST"; then
  die "$SOURCE_HOST still present in dist/"
fi
if grep -rlq "$SOURCE_PATH" "$DIST"; then
  die "$SOURCE_PATH still present in dist/"
fi

# Every local href/src must resolve inside dist/. Runs when python3 exists
# (it does on the Cloudflare build image); the grep guards above always run.
if command -v python3 > /dev/null 2>&1; then
  python3 - "$DIST" <<'PY'
import os, re, sys
from urllib.parse import unquote

root = sys.argv[1]
bad = []
for dirpath, _, files in os.walk(root):
    for name in sorted(files):
        if not name.endswith((".html", ".css")):
            continue
        path = os.path.join(dirpath, name)
        text = open(path, encoding="utf-8").read()
        for attr in re.findall(r'(?:href|src)="([^"]+)"', text):
            if attr.startswith(("http://", "https://", "mailto:", "#", "data:")):
                continue
            target = unquote(attr.split("#")[0])
            if not target:
                continue
            if target.startswith("/"):
                full = os.path.normpath(os.path.join(root, target.lstrip("/")))
            else:
                full = os.path.normpath(os.path.join(dirpath, target))
            if os.path.isdir(full):
                full = os.path.join(full, "index.html")
            if not os.path.exists(full):
                bad.append("%s -> %s" % (os.path.relpath(path, root), attr))

if bad:
    sys.stderr.write("broken links:\n  " + "\n  ".join(bad) + "\n")
    sys.exit(1)

print("local links ok")
PY
else
  echo "python3 not found; skipped the local link check"
fi

echo "rewrote $rewritten files for https://$ORIGIN"
echo "output: $DIST"
