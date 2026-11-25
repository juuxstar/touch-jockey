#!/bin/bash
# Builds TJCore (via build.sh unless --no-build) and runs the handoff coach and unlocks test (no audio).
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${1:-}" = "--no-build" ] || ./build.sh >/dev/null
swiftc -O -target arm64-apple-macos13.0 -I build/obj -L build/obj -lTJCore \
  -o build/obj/coach_test scripts/coach_test.swift
build/obj/coach_test
