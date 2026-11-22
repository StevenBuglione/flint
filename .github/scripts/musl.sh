#!/bin/sh
set -eu
# This script executes inside the digest-locked Alpine image. GitHub's Node
# actions stay on the glibc host; no glibc compatibility shim masks musl testing.
apk add --no-cache python3 build-base binutils clang cmake ninja meson perl pkgconf git coreutils curl \
  autoconf automake libtool bison flex linux-headers \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxscrnsaver-dev libxtst-dev
git config --global --add safe.directory /work
python3 tools/install_toolchains.py --compiler ldc --musl --destination /opt/flint-tools
arch=$(uname -m)
PATH="/opt/flint-tools/ldc2-1.43.0-alpine-$arch/bin:$PATH"
export PATH
python3 tools/ci.py platform --target "$FLINT_TARGET"
