#!/usr/bin/env bash
# Install a pinned aqua binary into $1 (default: ./.aqua-bin) after verifying
# its SHA-256 against the value recorded here (taken from
# aqua_<version>_checksums.txt of the aquaproj/aqua GitHub Release).
set -euo pipefail

AQUA_VERSION=v2.64.0
dest=${1:-.aqua-bin}

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

case "${os}_${arch}" in
  darwin_amd64) sum=64bc676871f2fe2683f57371e958963fc5a14b72b03e22b796fa228dcdeb353b ;;
  darwin_arm64) sum=f7f7890781bbd8863b04b61eb7bb40fe83add7097243c13da987ae9fb56d93b7 ;;
  linux_amd64) sum=b276e927ee2f4dc214831708c0843a91007bafa06f2f9fcd6ee1fd73fd165598 ;;
  linux_arm64) sum=7cc2b859333f40ef52eb62a1be3bfaa34dcbc27ef1c8bdc5bfaea7787597bc18 ;;
  *) echo "unsupported platform: ${os}_${arch}" >&2; exit 1 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
asset="aqua_${os}_${arch}.tar.gz"
curl -fsSL --retry 3 -o "$tmp/$asset" \
  "https://github.com/aquaproj/aqua/releases/download/${AQUA_VERSION}/${asset}"
if command -v sha256sum >/dev/null; then
  actual=$(sha256sum "$tmp/$asset" | cut -d' ' -f1)
else
  actual=$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)
fi
if [ "$actual" != "$sum" ]; then
  echo "checksum mismatch for $asset: got $actual, want $sum" >&2
  exit 1
fi
mkdir -p "$dest"
tar -xzf "$tmp/$asset" -C "$dest" aqua
"$dest/aqua" version
