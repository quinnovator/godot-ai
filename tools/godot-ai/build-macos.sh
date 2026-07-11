#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

if ! command -v uvx >/dev/null 2>&1; then
	echo "error: uvx is required; install uv from https://docs.astral.sh/uv/" >&2
	exit 127
fi
if ! command -v xcrun >/dev/null 2>&1; then
	echo "error: Xcode Command Line Tools are required; run 'xcode-select --install'" >&2
	exit 127
fi

# Nix may put GNU ar ahead of Apple's ar. Current Apple linkers reject the
# resulting archive alignment, so select the platform tools explicitly.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
exec uvx --from 'scons==4.10.1' scons \
  platform=macos \
  arch=arm64 \
  target=editor \
  dev_build=yes \
  generate_bundle=yes \
  vulkan=no \
  accesskit=no \
  angle=no \
  -j"${JOBS:-9}" \
  "$@"
