#!/usr/bin/env bash
# 1) EPANET 3 load → save (ProjectWriter) → temp .inp
# 2) EPANET 2.2 runepanet2 on that file
# Requires: swift build in EPANET3App, scripts/build_epanet22_cli.sh run once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EP2="$ROOT/EPANET2.2-2.2.0/build/runepanet2"
CLI="$ROOT/EPANET3App/.build/debug/EPANET3CLI"
NET1="${1:-$ROOT/epanet  resource/example/Epanet 管网/net1.inp}"
if [[ ! -x "$EP2" ]]; then
  echo "Run first: $ROOT/scripts/build_epanet22_cli.sh" >&2
  exit 1
fi
if [[ ! -x "$CLI" ]]; then
  echo "Build EPANET3App: (cd $ROOT/EPANET3App && swift build)" >&2
  exit 1
fi
if [[ ! -f "$NET1" ]]; then
  echo "Input not found: $NET1" >&2
  exit 1
fi
RT=$("$CLI" --round-trip-save-run "$NET1" 2>&1 | sed -n 's/^Round-trip save: //p')
if [[ -z "$RT" ]]; then
  echo "Could not parse round-trip path from EPANET3CLI" >&2
  exit 1
fi
RPT=$(mktemp /tmp/epanet22_rt_XXXXXX.rpt)
OUT=$(mktemp /tmp/epanet22_rt_XXXXXX.out)
echo "Round-trip INP: $RT"
"$EP2" "$RT" "$RPT" "$OUT"
echo "EPANET 2.2: OK"
rm -f "$RPT" "$OUT"
