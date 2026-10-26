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
