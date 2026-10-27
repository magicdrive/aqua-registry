#!/usr/bin/env bash
# Tests of ci/lib.sh's check_release_checksums with a stub curl that serves
# Release checksum files from a temporary directory: a matching checksum
# passes, and a mismatch, a missing or unreadable aqua-checksums.json, or one
# that records no checksum fail (a cross-check that checked nothing must not
# pass).
#
# Usage: ci/test-lib.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=ci/lib.sh
. "$here/lib.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/releases/magicdrive/t/v1.2.1" "$tmp/releases/magicdrive/kjak/v0.0.4"
# curl ... URL: prints $RELEASES/<owner>/<repo>/<tag>/<file> for
# https://github.com/<owner>/<repo>/releases/download/<tag>/<file>, or fails
# as curl -f does on a 404.
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/sh
for url; do :; done
path=${url#https://github.com/}
owner_repo=${path%%/releases/download/*}
rest=${path#*/releases/download/}
f="$RELEASES/$owner_repo/$rest"
[ -f "$f" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
cat "$f"
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH" RELEASES="$tmp/releases"

sum_t=1111111111111111111111111111111111111111111111111111111111111111
sum_k=2222222222222222222222222222222222222222222222222222222222222222
echo "$sum_t  t_1.2.1_linux_amd64.tar.gz" > "$tmp/releases/magicdrive/t/v1.2.1/t_checksums.txt"
echo "$sum_k  kjak_0.0.4_linux_amd64.tar.gz" > "$tmp/releases/magicdrive/kjak/v0.0.4/kjak_0.0.4_checksums.txt"
entry() { printf '{"id": "github_release/github.com/magicdrive/%s", "checksum": "%s", "algorithm": "sha256"}' "$1" "$2"; }
good="{\"checksums\": [$(entry t/v1.2.1/t_1.2.1_linux_amd64.tar.gz "$sum_t"), $(entry kjak/v0.0.4/kjak_0.0.4_linux_amd64.tar.gz "$sum_k")]}"
bad="{\"checksums\": [$(entry t/v1.2.1/t_1.2.1_linux_amd64.tar.gz "$sum_k")]}"

failed=0
# expect NAME WANT(pass|fail) FILE
expect() {
  local name=$1 want=$2 file=$3 got out
  out=$( (failures=0; check_release_checksums "$file"; echo "failures=$failures") 2>&1) || true
  case "$out" in
    *failures=0) got=pass ;;
    *failures=[1-9]*) got=fail ;;
    *) got="error" ;;
  esac
  if [ "$got" = "$want" ]; then
    echo "ok   $name ($got)"
  else
    echo "FAIL $name: $got, want $want"
    printf '%s\n' "$out" | sed 's/^/     | /'
    failed=1
  fi
}

printf '%s\n' "$good" > "$tmp/good.json"
printf '%s\n' "$bad" > "$tmp/bad.json"
printf '{"checksums": []}\n' > "$tmp/empty.json"
printf '{"checksums": [\n' > "$tmp/broken.json"

expect "matching checksums" pass "$tmp/good.json"
expect "a checksum differs from the release" fail "$tmp/bad.json"
expect "no aqua-checksums.json" fail "$tmp/missing.json"
expect "unparsable aqua-checksums.json" fail "$tmp/broken.json"
expect "no checksum recorded" fail "$tmp/empty.json"

[ "$failed" -eq 0 ] || { echo "test-lib: FAILED"; exit 1; }
echo "test-lib: ok"
