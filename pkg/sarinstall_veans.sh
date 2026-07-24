#!/usr/bin/env bash
set -euo pipefail

version="v2.4.0"

file="veans-${version}-darwin-10.15-arm64"
archive="${file}-full.zip"
url="https://github.com/go-vikunja/vikunja/releases/download/${version}/${archive}"

curl -LJO "${url}"

install_loc="${HOME}/.local/bin/veans-${version}"
mkdir -p "${install_loc}"
unzip "./${archive}" -d "${install_loc}"

chmod +x "${install_loc}/${file}"
ln -s -f "${install_loc}/${file}" "${HOME}/.local/bin/veans"

rm -rf "./${archive}"
