#!/usr/bin/env bash
# Tests of ci/tamper.sh with the real aqua: the tampered checksum must PASS
# only when aqua rejects it as "checksum is invalid". A failure injected into
# the run must make ci/tamper.sh FAIL and name the class of that failure:
#
#   nonexistent version      TAMPER_PKG=magicdrive/t@v9.9.9       not_found
#   broken registry          REGISTRY=<invalid YAML>              registry
#   aqua not in PATH         AQUA=aqua, PATH without aqua         tool_missing
#   aqua path does not exist AQUA=<missing file>                  tool_missing
#   network down on install  HTTPS_PROXY=<closed port>            network
#   unwritable AQUA_ROOT_DIR chmod 555 before install             permission
#   broken archive           local HTTP package whose file is not
#                            a tar.gz, with its real checksum     archive
#   install hangs            TAMPER_TIMEOUT=10, install sleeps    timeout
#
# Faults that must hit `aqua install` (after update-checksum succeeded) are
# injected by a wrapper passed as AQUA that changes the environment of the
# install command and then execs the real aqua.
#
# Usage: AQUA=/path/to/aqua ci/test-tamper.sh   (needs network, jq, python3)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
AQUA=${AQUA:-aqua}
real=$(command -v "$AQUA") || { echo "aqua not found: $AQUA" >&2; exit 1; }
real=$(cd "$(dirname "$real")" && pwd)/$(basename "$real")
export REAL_AQUA=$real

tmp=$(mktemp -d)
server=
# chmod: the permission case leaves a read-only directory behind.
trap '[ -z "$server" ] || kill "$server" 2> /dev/null || true; chmod -R u+w "$tmp" 2> /dev/null || true; rm -rf "$tmp"' EXIT

# wrapper NAME < BODY: an aqua wrapper that runs BODY (sh, read from stdin)
# before `aqua install`, then execs the real aqua.
wrapper() {
  {
    cat <<'SH'
#!/bin/sh
if [ "$1" = install ]; then
SH
    cat
    cat <<'SH'
fi
exec "$REAL_AQUA" "$@"
SH
  } > "$tmp/$1"
  chmod +x "$tmp/$1"
}
wrapper net.sh <<'SH'
  export HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
  export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 NO_PROXY= no_proxy=
SH
wrapper perm.sh <<'SH'
  mkdir -p "$AQUA_ROOT_DIR" && chmod 555 "$AQUA_ROOT_DIR"
SH
wrapper hang.sh <<'SH'
  exec sleep 300
SH
# Restores the real checksum, so that aqua gets past verification and fails
# to unarchive.
wrapper restore.sh <<'SH'
  cp aqua-checksums.json.bak aqua-checksums.json
SH

printf 'packages:\n  - type: github_release\n   repo_owner: [\n' > "$tmp/broken.yaml"

# A PATH without any directory that has an aqua.
nopath=
while IFS= read -r d; do
  [ -n "$d" ] && [ ! -x "$d/aqua" ] && nopath=${nopath:+$nopath:}$d
done <<< "${PATH//:/$'\n'}"

# A local HTTP package whose file is random bytes named t.tar.gz.
mkdir -p "$tmp/srv"
head -c 4096 /dev/urandom > "$tmp/srv/t.tar.gz"
python3 -I -u -m http.server 0 --bind 127.0.0.1 --directory "$tmp/srv" > "$tmp/srv.log" 2>&1 &
server=$!
port=
for _ in $(seq 50); do
  port=$(sed -n 's/.* port \([0-9][0-9]*\).*/\1/p' "$tmp/srv.log")
  [ -n "$port" ] && break
  sleep 0.1
done
[ -n "$port" ] || { echo "the HTTP server did not start" >&2; cat "$tmp/srv.log" >&2; exit 1; }
cat > "$tmp/http-registry.yaml" <<EOF
packages:
  - type: http
    name: local/broken
    url: http://127.0.0.1:$port/t.tar.gz
    format: tar.gz
    files:
      - name: t
EOF

failed=0
# expect NAME WANT(pass|<class>) [VAR=VALUE...]: runs ci/tamper.sh with the
# variables set.
expect() {
  local name=$1 want=$2 out status=0 got
  shift 2
  out=$(env "$@" "$here/tamper.sh" 2>&1) || status=$?
  if [ "$status" -eq 0 ] && grep -q '^PASS tampered checksum is rejected' <<< "$out"; then
    got=pass
  elif [ "$status" -ne 0 ] && grep -q '^FAIL tampered checksum' <<< "$out"; then
    got=$(sed -n 's/^FAIL tampered checksum: .*[(,] *\([a-z_]*\))$/\1/p' <<< "$out" | head -1)
    got=${got:-fail}
  else
    got="error(status $status)"
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name ($got)"
  else
    echo "FAIL $name: got $got, want $want"
    printf '%s\n' "$out" | sed 's/^/     | /'
    failed=1
  fi
}

expect "tampered checksum" pass AQUA="$real"
expect "nonexistent version" not_found AQUA="$real" TAMPER_PKG=magicdrive/t@v9.9.9
expect "broken registry" registry AQUA="$real" REGISTRY="$tmp/broken.yaml"
expect "aqua not in PATH" tool_missing AQUA=aqua PATH="$nopath"
expect "aqua path does not exist" tool_missing AQUA="$tmp/missing/aqua"
expect "network down on install" network AQUA="$tmp/net.sh"
expect "unwritable AQUA_ROOT_DIR" permission AQUA="$tmp/perm.sh"
expect "broken archive" archive AQUA="$tmp/restore.sh" REGISTRY="$tmp/http-registry.yaml" TAMPER_PKG=local/broken@v1.0.0
expect "install hangs" timeout AQUA="$tmp/hang.sh" TAMPER_TIMEOUT=10
# The same broken archive with the tampered checksum: aqua verifies before
# unarchiving, so this is a checksum rejection.
expect "broken archive, tampered checksum" pass AQUA="$real" REGISTRY="$tmp/http-registry.yaml" TAMPER_PKG=local/broken@v1.0.0

exit "$failed"
