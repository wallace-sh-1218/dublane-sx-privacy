#!/usr/bin/env bash
#
# Mirror the published site into the Gitee repository.
#
# The Gitee repository has the SAME name (dublane-sx-privacy), so both Pages
# hosts serve the site under the same path (/dublane-sx-privacy/). Only the
# host differs, so the mirror is a straight copy plus one host swap.
#
# Usage:
#   scripts/sync-gitee.sh                    # copy, commit and push
#   PUSH=0 scripts/sync-gitee.sh             # copy and commit, no push
#   scripts/sync-gitee.sh /path/to/mirror    # alternate local mirror clone
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="${1:-${GITEE_DIR:-/Users/wufengjuan/xdt/code/git/gitee/dublane-sx-privacy}}"
SRC_HOST="wallace-sh-1218.github.io"
MIRROR_HOST="wallace-sh-1218.gitee.io"
PUSH="${PUSH:-1}"

die() { echo "error: $*" >&2; exit 1; }

[ -d "$DST/.git" ] || die "$DST is not a git clone"
[ "$SRC" != "$DST" ] || die "source and mirror are the same directory"
case "$(git -C "$DST" config --get remote.origin.url || true)" in
  *gitee.com*) ;;
  *) die "$DST is not a Gitee clone; refusing to overwrite it" ;;
esac

SHA="$(git -C "$SRC" rev-parse --short HEAD)"
SUBJECT="$(git -C "$SRC" log -1 --format=%s)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Publish exactly what is committed on HEAD, never the working tree.
git -C "$SRC" archive HEAD | tar -x -C "$TMP"

# The sync script is repo tooling, not part of the published site.
rm -rf "$TMP/scripts"

# Host swap for the absolute URLs (privacy links, hreflang, canonical).
# The path segment stays identical, so nothing else needs rewriting.
find "$TMP" -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' \) -print0 |
  while IFS= read -r -d '' file; do
    sed -i '' "s/${SRC_HOST}/${MIRROR_HOST}/g" "$file"
  done

if grep -rl "$SRC_HOST" "$TMP" > /dev/null 2>&1; then
  die "$SRC_HOST still present in the mirror"
fi

# Mirror-only README, regenerated on every sync.
cat > "$TMP/README.md" <<'EOF'
# dublane-sx-privacy (Gitee mirror)

This repository is a **generated mirror** of the Dublane help and privacy
site. Files here are overwritten on every sync — do not edit them directly.

- Source of truth: https://github.com/wallace-sh-1218/dublane-sx-privacy
- Published here: https://wallace-sh-1218.gitee.io/dublane-sx-privacy/
- Published on GitHub Pages: https://wallace-sh-1218.github.io/dublane-sx-privacy/

## How to update

From the source repository:

```bash
scripts/sync-gitee.sh          # copy, commit and push
PUSH=0 scripts/sync-gitee.sh   # copy and commit only
```

The only difference from the source is the host inside absolute URLs
(`wallace-sh-1218.github.io` → `wallace-sh-1218.gitee.io`). Both Pages hosts
serve the site under the same `/dublane-sx-privacy/` path, so every relative
link works unchanged.

After a push, Gitee Pages has to be refreshed by hand: 仓库 → 服务 →
Gitee Pages → 更新.

## 中文

本仓库是 Dublane 帮助中心与隐私政策页面的**自动镜像**，请勿直接修改文件。
源仓库在 GitHub；如需更新，在源仓库执行 `scripts/sync-gitee.sh`，然后在
Gitee Pages 页面点一次「更新」。
EOF

# Every local href/src must resolve inside the mirror.
python3 - "$TMP" <<'PY'
import os, re, sys
from urllib.parse import unquote

root = sys.argv[1]
BASE_PATH = "/dublane-sx-privacy/"
bad = []
for dirpath, _, files in os.walk(root):
    for name in files:
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
                # Root-absolute paths are resolved by the Pages host, where
                # "/dublane-sx-privacy/" *is* the repository root on both hosts.
                if target.startswith(BASE_PATH):
                    target = target[len(BASE_PATH):]
                full = os.path.normpath(os.path.join(root, target.lstrip("/")))
            else:
                full = os.path.normpath(os.path.join(dirpath, target))
            if os.path.isdir(full):
                full = os.path.join(full, "index.html")
            if not os.path.exists(full):
                bad.append("%s: %s" % (os.path.relpath(path, root), attr))
if bad:
    sys.stderr.write("broken local links:\n  " + "\n  ".join(bad) + "\n")
    sys.exit(1)

print("local links ok")
PY

# Replace the checkout (keep .git) so deletions are mirrored too.
find "$DST" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -R "$TMP"/. "$DST"/

cd "$DST"
git add -A
if git diff --cached --quiet; then
  echo "mirror already up to date"
else
  git commit -q -m "mirror: ${SUBJECT} (${SHA})"
  echo "committed $(git log -1 --format='%h %s')"
fi

if [ "$PUSH" != "0" ]; then
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' > /dev/null 2>&1; then
    git push origin HEAD
  else
    git push -u origin master
  fi
fi

echo "mirror: $DST"
