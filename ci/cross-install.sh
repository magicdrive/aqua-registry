#!/usr/bin/env bash
# Resolve and install registry entries for every platform listed in
# ci/cross-cases.txt by overriding the target platform with AQUA_GOOS and
# AQUA_GOARCH. Each case downloads the real Release asset, verifies its SHA-256
# (aqua-checksums.json is generated first, then required) and unarchives it.
# Binaries are not executed here; ci/smoke.sh runs them on native runners.
#
# Usage: AQUA=/path/to/aqua ci/cross-install.sh [cases-file]
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
REGISTRY=$(cd "$here/.." && pwd)/registry.yaml
AQUA=${AQUA:-aqua}
cases=${1:-$here/cross-cases.txt}
# shellcheck source=ci/lib.sh
. "$here/lib.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export AQUA_ROOT_DIR=$work/root AQUA_LOG_COLOR=never AQUA_POLICY_CONFIG=$work/aqua-policy.yaml
write_policy "$work"

all_envs="darwin/amd64 darwin/arm64 linux/amd64 linux/arm64 windows/amd64 windows/arm64"
failures=0
n=0

while read -r pkg version envs expect; do
  case "$pkg" in "" | \#*) continue ;; esac
  [ "$envs" = all ] && envs=$all_envs
  for env in $envs; do
    n=$((n + 1))
    dir=$work/case-$n
    mkdir -p "$dir"
    write_config "$dir" true "$pkg@$version"
    export AQUA_GOOS=${env%/*} AQUA_GOARCH=${env#*/}
    log=$dir/log.txt
    got=error
    upc=0
    (cd "$dir" && "$AQUA" --log-level debug update-checksum) > "$log" 2>&1 || upc=$?
    if (cd "$dir" && "$AQUA" --log-level debug install --all) >> "$log" 2>&1; then
      if grep -q "the package isn't supported on this environment" "$log"; then
        got=unsupported
      elif [ "$upc" -eq 0 ] && grep -q '"algorithm": "sha256"' "$dir/aqua-checksums.json" &&
        [ -d "$AQUA_ROOT_DIR/pkgs/github_release/github.com/$pkg/$version" ]; then
        got=ok
      fi
    elif grep -q 'no asset is released for this version' "$log"; then
      got=no_asset
    fi
    if [ "$got" = "$expect" ]; then
      echo "PASS $pkg@$version $env: $got"
    else
      echo "FAIL $pkg@$version $env: expected $expect, got $got"
      grep -E 'ERR|WRN' "$log" | tail -5 || true
      failures=$((failures + 1))
    fi
  done
  unset AQUA_GOOS AQUA_GOARCH
done < "$cases"

# Negative test: a wrong checksum must make the installation fail, and fail
# because of the checksum (ci/tamper.sh).
if ! AQUA=$AQUA REGISTRY=$REGISTRY "$here/tamper.sh"; then
  failures=$((failures + 1))
fi

echo "cases: $n, failures: $failures"
[ "$failures" -eq 0 ]
