#!/bin/bash
# Builds TJCore (via build.sh unless --no-build) and runs the muted mixer engine test.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${1:-}" = "--no-build" ] || ./build.sh >/dev/null
swiftc -O -target arm64-apple-macos13.0 -I build/obj -L build/obj -lTJCore \
  -o build/obj/mixer_test scripts/mixer_test.swift
build/obj/mixer_test
