# shellcheck shell=bash
# Shared helpers for the CI scripts. Source it; do not execute it.
# Requires: AQUA (path to the aqua binary), REGISTRY (absolute path to registry.yaml).

# write_policy <dir>: allow every package of the local registry.
write_policy() {
  cat > "$1/aqua-policy.yaml" <<YAML
registries:
  - type: local
    name: local
    path: $REGISTRY
packages:
  - registry: local
YAML
}

# write_config <dir> <require_checksum> <pkg@version>...
write_config() {
  local dir=$1 require=$2
  shift 2
  {
    echo "checksum:"
    echo "  enabled: true"
    echo "  require_checksum: $require"
    echo "registries:"
    echo "  - name: local"
    echo "    type: local"
    echo "    path: $REGISTRY"
    echo "packages:"
    for p in "$@"; do
      echo "  - name: $p"
      echo "    registry: local"
    done
  } > "$dir/aqua.yaml"
}

# check_release_checksums <aqua-checksums.json>: every checksum aqua recorded
# must match the checksum file published in its GitHub Release. Prints a
# PASS/FAIL line per checksum and adds the FAILs to $failures. A file that
# cannot be read, or that records no checksum, is a FAIL too: jq's status is
# checked before the loop (a process substitution would drop it).
check_release_checksums() {
  local id sum rest repo tag asset v name f published want entries
  if ! entries=$(jq -er '.checksums[] | "\(.id) \(.checksum)"' "$1"); then
    echo "FAIL checksum: no checksum can be read from $1"
    failures=$((failures + 1))
    return 0
  fi
  while read -r id sum; do
    rest=${id#github_release/github.com/}
    repo=${rest%%/*}; rest=${rest#*/}
    repo=$repo/${rest%%/*}; rest=${rest#*/}
    tag=${rest%%/*}; asset=${rest#*/}
    v=${tag#v}
    name=${repo#*/}
    published=
    for f in "${name}_checksums.txt" "${name}_${v}_checksums.txt"; do
      if published=$(curl -fsSL --retry 3 "https://github.com/$repo/releases/download/$tag/$f" 2>/dev/null); then
        break
      fi
    done
    want=$(printf '%s\n' "$published" | awk -v a="$asset" '$2 == a { print toupper($1) }')
    if [ -n "$want" ] && [ "$want" = "$sum" ]; then
      echo "PASS checksum $repo $tag $asset"
    else
      echo "FAIL checksum $repo $tag $asset: aqua=$sum release=${want:-missing}"
      failures=$((failures + 1))
    fi
  done <<< "$entries"
}

# run_bounded <seconds> <command>...: runs the command, killed after <seconds>
# (status 124, as timeout(1) reports it). Without timeout(1) the command runs
# unbounded and the CI job's timeout-minutes is the only limit.
run_bounded() {
  local limit=$1
  shift
  if command -v timeout > /dev/null; then
    timeout -k 10 "$limit" "$@"
  else
    "$@"
  fi
}

# classify_aqua_failure <status> <log>: prints why an aqua command failed,
# from its exit status and the messages aqua v2.64.0 logs:
#   timeout            status 124 or 137 (run_bounded killed it)
#   tool_missing       status 126 or 127 (aqua is not found or not executable)
#   checksum_mismatch  error="checksum is invalid"
#   permission         permission denied, operation not permitted, read-only
#   network            refused, unresolved, reset or timed out connections,
#                      proxy errors, retries given up, 5xx, rate limits
#   archive            the downloaded file cannot be unarchived
#   not_found          404, no asset for the version, unsupported platform
#   registry           the registry or the configuration cannot be parsed
#   unknown            anything else (including status 0)
# The first matching class wins, in the order above.
classify_aqua_failure() {
  local status=$1 log=$2 errs
  case "$status" in
    124 | 137) echo timeout; return 0 ;;
    126 | 127) echo tool_missing; return 0 ;;
  esac
  errs=$(grep -E ' ERR |command not found|No such file or directory' "$log" 2>/dev/null || true)
  if grep -q -F 'error="checksum is invalid"' <<< "$errs"; then
    echo checksum_mismatch
  elif grep -q -i -E 'permission denied|operation not permitted|read-only file system' <<< "$errs"; then
    echo permission
  elif grep -q -i -E 'connection refused|no such host|i/o timeout|TLS handshake|proxyconnect|connection reset|network is unreachable|giving up after|context deadline exceeded|: 5[0-9][0-9] |rate limit' <<< "$errs"; then
    echo network
  elif grep -q -E 'identify the format|unarchive|invalid header|not a valid zip|unexpected EOF' <<< "$errs"; then
    echo archive
  elif grep -q -E '404 Not Found|no asset is released|is not found|isn.t supported on this environment' <<< "$errs"; then
    echo not_found
  elif grep -q -E 'parse the registry|yaml: |unmarshal|configuration file' <<< "$errs"; then
    echo registry
  else
    echo unknown
  fi
}
