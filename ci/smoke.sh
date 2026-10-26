#!/usr/bin/env bash
# Install the latest release of every package natively with aqua, run each
# command and check the version it reports. Also checks that the checksums
# aqua recorded match the checksum file published in each GitHub Release.
#
# Usage: AQUA=/path/to/aqua ci/smoke.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
REGISTRY=$(cd "$here/.." && pwd)/registry.yaml
AQUA=${AQUA:-aqua}
# shellcheck source=ci/lib.sh
. "$here/lib.sh"

# <package> <version>
packages="
magicdrive/ark v6.7.2
magicdrive/enma v2.1.2
magicdrive/goreg v1.3.11
magicdrive/kjak v0.0.4
magicdrive/git-parallel v1.0.3
magicdrive/hephaestus v1.2.0
magicdrive/kirke v1.2.8
magicdrive/t v1.2.1
"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export AQUA_ROOT_DIR=$work/root AQUA_LOG_COLOR=never AQUA_POLICY_CONFIG=$work/aqua-policy.yaml
# The links in $AQUA_ROOT_DIR/bin go through aqua-proxy, which needs aqua in PATH.
aqua_dir=$(dirname "$(command -v "$AQUA")")
export PATH=$AQUA_ROOT_DIR/bin:$aqua_dir:$PATH
write_policy "$work"

specs=()
while read -r pkg version; do
  [ -n "$pkg" ] && specs+=("$pkg@$version")
done <<< "$packages"
write_config "$work" true "${specs[@]}"
(cd "$work" && "$AQUA" update-checksum && "$AQUA" install --all)

failures=0
check() { # check <name> <want> <got>
  if printf '%s\n' "$3" | grep -qF -- "$2"; then
    echo "PASS $1: $(printf '%s\n' "$3" | grep -F -- "$2" | head -1)"
  else
    echo "FAIL $1: want '$2', got '$3'"
    failures=$((failures + 1))
  fi
}

while read -r pkg version; do
  [ -n "$pkg" ] || continue
  cmd=${pkg#*/}
  path=$(cd "$work" && "$AQUA" which "$cmd")
  echo "== $pkg@$version -> $path"
  case "$cmd" in
    t)
      # t has no --version; --help prints USAGE and exits 1, and the
      # version is recorded in the bundled man page (.TH line).
      check "t --help" "USAGE:" "$(cd "$work" && t --help 2>&1 || true)"
      check "t.1 .TH" "\"$version\"" "$(grep '^\.TH' "$(dirname "$path")/t.1")"
      ;;
    git-parallel)
      check "$cmd --version" "git-parallel $version" "$(cd "$work" && git-parallel --version 2>&1)"
      ;;
    hephaestus)
      check "$cmd --version" "hephaestus $version" "$(cd "$work" && hephaestus --version 2>&1)"
      ;;
    *)
      check "$cmd --version" "$cmd version $version" "$(cd "$work" && "$cmd" --version 2>&1)"
      ;;
  esac
done <<< "$packages"

# Cross-check aqua-checksums.json against the checksum files of the Releases.
while read -r id sum; do
  rest=${id#github_release/github.com/}
  repo=${rest%%/*}; rest=${rest#*/}
  repo=$repo/${rest%%/*}; rest=${rest#*/}
  tag=${rest%%/*}; asset=${rest#*/}
  v=${tag#v}
  name=${repo#*/}
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
done < <(jq -r '.checksums[] | "\(.id) \(.checksum)"' "$work/aqua-checksums.json")

echo "failures: $failures"
[ "$failures" -eq 0 ]
