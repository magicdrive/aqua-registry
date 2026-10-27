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
