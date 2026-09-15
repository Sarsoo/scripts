#!/usr/bin/env bash

pushd ~/.local/bin
curl -s https://api.github.com/repos/macropower/kat/releases/latest | \
  jq -r ".assets[] |
    select(.name | test(\"kat_$(uname -s)_$(uname -m).tar.gz\")) |
    .browser_download_url" | \
  xargs curl -L | tar -xz
popd
