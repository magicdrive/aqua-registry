#!/usr/bin/env bash
# Negative test: a wrong checksum in aqua-checksums.json must make the
# installation fail, and it must fail *because of* that checksum.
#
# An installation that fails for another reason (network, permission, a
# broken archive or registry, a missing aqua, a timeout, ...) says nothing
# about checksum verification, so it is a FAIL here, reported with the class
# of the failure (see classify_aqua_failure in ci/lib.sh). The test PASSes
# only when all of these hold:
#   - aqua update-checksum succeeds and records sha256 checksums for the
#     package, and every one of them is replaced with zeros;
#   - aqua install exits with status 1 (aqua's error status) within the time
#     limit;
#   - the log has `ERR install the package` for the package with
#     expected_checksum=000...0 and error="checksum is invalid";
#   - every other ERR line is aqua's summary of that failure;
#   - nothing of the package was unarchived into AQUA_ROOT_DIR.
#
# Usage: AQUA=/path/to/aqua ci/tamper.sh
# Environment (defaults in brackets; the overrides exist for ci/test-tamper.sh):
#   AQUA            aqua command [aqua]
#   REGISTRY        registry.yaml [the one of this repository]
#   TAMPER_PKG      package to install [magicdrive/t@v1.2.1]
#   TAMPER_TIMEOUT  seconds allowed for each aqua command [600]
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
REGISTRY=${REGISTRY:-$(cd "$here/.." && pwd)/registry.yaml}
AQUA=${AQUA:-aqua}
pkg=${TAMPER_PKG:-magicdrive/t@v1.2.1}
limit=${TAMPER_TIMEOUT:-600}
# shellcheck source=ci/lib.sh
. "$here/lib.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dir=$work/tamper
mkdir -p "$dir"
# A root of its own: a package already in the cache would be linked without
# being downloaded, so its checksum would not be verified at all.
export AQUA_ROOT_DIR=$dir/root AQUA_LOG_COLOR=never AQUA_POLICY_CONFIG=$work/aqua-policy.yaml
unset AQUA_GOOS AQUA_GOARCH
write_policy "$work"
write_config "$dir" true "$pkg"
zeros=0000000000000000000000000000000000000000000000000000000000000000

fail() {
  echo "FAIL tampered checksum: $*"
  if [ -f "$dir/log.txt" ]; then
    grep -E ' ERR |command not found|No such file' "$dir/log.txt" | tail -5 | sed 's/^/     | /' || true
  fi
  exit 1
}

status=0
(cd "$dir" && run_bounded "$limit" "$AQUA" update-checksum) > "$dir/log.txt" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  fail "update-checksum failed before anything was tampered with (status $status, $(classify_aqua_failure "$status" "$dir/log.txt"))"
fi
recorded=$(jq '[.checksums[] | select(.algorithm == "sha256")] | length' "$dir/aqua-checksums.json" 2>/dev/null || echo 0)
[ "$recorded" -gt 0 ] || fail "update-checksum recorded no sha256 checksum for $pkg"

sed -i.bak -E "s/\"checksum\": \"[0-9A-F]{64}\"/\"checksum\": \"$zeros\"/" "$dir/aqua-checksums.json"
tampered=$(jq --arg z "$zeros" '[.checksums[] | select(.checksum == $z)] | length' "$dir/aqua-checksums.json")
[ "$tampered" -eq "$recorded" ] || fail "only $tampered of $recorded checksums were replaced"

status=0
(cd "$dir" && run_bounded "$limit" "$AQUA" install --all) > "$dir/install.log" 2>&1 || status=$?
cat "$dir/install.log" >> "$dir/log.txt"
log=$dir/install.log

if [ "$status" -eq 0 ]; then
  fail "the tampered checksum was accepted (install succeeded)"
fi
# The ERR lines that are neither the checksum rejection of this package nor
# aqua's summary of it. A retried request that failed is logged as
# `ERR request failed` even when a later attempt succeeds; if the request
# never succeeds, aqua logs a final ERR for it, which is caught here.
others=$(grep ' ERR ' "$log" |
  grep -v -F 'error="checksum is invalid"' |
  grep -v -F 'ERR request failed' |
  grep -v -F 'ERR aqua failed' || true)
summary=$(grep -F 'ERR aqua failed' "$log" | grep -v -F 'error="install packages: it failed to install some packages"' || true)
if [ -n "$others$summary" ]; then
  printf '%s\n%s\n' "$others" "$summary" > "$work/others.log"
  fail "install failed for another reason (status $status, $(classify_aqua_failure "$status" "$work/others.log"))"
fi
if [ "$status" -ne 1 ]; then
  fail "install exited with status $status, want 1 ($(classify_aqua_failure "$status" "$log"))"
fi
if ! grep ' ERR install the package ' "$log" |
  grep -F "package_name=${pkg%@*} " |
  grep -F "expected_checksum=$zeros " |
  grep -q -F 'error="checksum is invalid"'; then
  fail "install failed without rejecting the tampered checksum of $pkg ($(classify_aqua_failure "$status" "$log"))"
fi
if [ -d "$AQUA_ROOT_DIR/pkgs" ] &&
  [ -n "$(find "$AQUA_ROOT_DIR/pkgs" -type f ! -path '*/aquaproj/aqua-proxy/*')" ]; then
  fail "files of $pkg were unarchived although its checksum was rejected"
fi
echo "PASS tampered checksum is rejected ($pkg: checksum is invalid, status 1)"
