#!/bin/bash
# Sample-accurate test of snapped Flick timing: prints how far from the heard bar each flick lands.
# Optional argument: extra lead in ms (MixEngine.renderLead) to try.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/obj
cp scripts/flick_timing.swift build/obj/main.swift
swiftc -O -target arm64-apple-macos13.0 -module-name FlickTiming -o build/obj/flick_timing Sources/TJCore/*.swift build/obj/main.swift
build/obj/flick_timing "${1:-0}"
