#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Sticky Blood requires Python 3 for safe DLL verification and patching." >&2
  exit 1
fi
exec python3 "$ROOT/tools/sticky_blood.py" install "$@"
