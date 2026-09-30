#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
swift test --disable-sandbox --cache-path "$PWD/.cache/swiftpm"
