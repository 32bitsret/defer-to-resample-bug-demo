#!/usr/bin/env bash
# Run the demo test against stock control-arena 20.0.1 and the fixed fork branch.
# Requires: uv (https://docs.astral.sh/uv/) and git. No API keys or Docker needed.
set -uo pipefail
cd "$(dirname "$0")"
PY="${PYTHON_VERSION:-3.12}"
mkdir -p results

run_target() {
  local target="$1" reqs="$2" out="$3" venv=".venv-$1"
  echo ">>> [$target] creating $venv"
  uv venv -q --clear --python "$PY" "$venv"
  uv pip install -q --python "$venv/bin/python" -r "$reqs"
  echo ">>> [$target] running pytest -> $out"
  {
    echo "# target: $target  (requirements: $reqs)"
    echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# command: DEMO_TARGET=$target $venv/bin/python -m pytest -v -s -rA"
    echo
    DEMO_TARGET="$target" "$venv/bin/python" -m pytest -v -s -rA 2>&1
    rc=$?
    echo
    echo "# pytest exit code: $rc"
  } > "$out"
  tail -n 3 "$out"
}

run_target stock requirements-stock.txt results/stock-20.0.1.txt
run_target fixed requirements-fixed.txt results/fixed.txt
# Cross-check: stock 20.0.1 against the *fixed* expectations must fail.
{
  echo "# cross-check: stock 20.0.1 venv, DEMO_TARGET=fixed (expected to FAIL)"
  echo
  DEMO_TARGET=fixed .venv-stock/bin/python -m pytest -v -s -rA 2>&1
  rc=$?
  echo
  echo "# pytest exit code: $rc"
} > results/cross-check-stock-vs-fixed-expectations.txt
tail -n 3 results/cross-check-stock-vs-fixed-expectations.txt

python3 scripts/side_by_side.py results/stock-20.0.1.txt results/fixed.txt > results/side-by-side.md
echo ">>> wrote results/side-by-side.md"
