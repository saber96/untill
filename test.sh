#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
sources=()
for source in Sources/*.swift; do
    [[ "$source" == Sources/main.swift ]] || sources+=("$source")
done
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$scratch/modules" "${sources[@]}" Tests/main.swift -o "$scratch/UntillTests"
"$scratch/UntillTests"
