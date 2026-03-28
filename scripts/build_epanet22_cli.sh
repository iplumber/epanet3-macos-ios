#!/usr/bin/env bash
# Build EPANET 2.2 command-line driver next to SRC_engines (not linked into SwiftPM / Xcode).
# Requires: clang, EPANET2.2-2.2.0/SRC_engines/*.c unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/EPANET2.2-2.2.0/SRC_engines"
OUT_DIR="$ROOT/EPANET2.2-2.2.0/build"
OUT="$OUT_DIR/runepanet2"
if [[ ! -d "$SRC" ]]; then
  echo "Missing: $SRC" >&2
  exit 1
fi
mkdir -p "$OUT_DIR"
clang -std=c99 -O2 -Wall -o "$OUT" "$SRC"/*.c -lm
echo "Built: $OUT"
echo "Usage: $OUT <input.inp> <report.txt> [output.bin]"
