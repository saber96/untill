#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/Untill.iconset"
swift -module-cache-path "$scratch/modules" MakeIcon.swift "$scratch/Untill.iconset"
iconutil -c icns "$scratch/Untill.iconset" -o Untill.icns
