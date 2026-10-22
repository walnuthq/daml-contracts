#!/usr/bin/env bash
#
# Demo: dpm trace test as a Daml Script unit-test runner / CI gate.
#
#   1. Green run   — all unit tests pass; full transaction trees are rendered.
#   2. Regression  — weaken an invariant in the contract.
#   3. Red run     — the guard test fails; dpm trace pinpoints the source line and
#                    returns a non-zero exit code (the CI gate).
#   4. Revert      — restore the contract.
#
# Overrides: DAML=<dpm|damlc> DPM_BIN=<dpm> DPM_HOME=<dpm home> COLOR=auto|always|never
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLOR="${COLOR:-auto}"

# Resolve the Daml toolchain; a bare name is resolved on PATH.
DAML="${DAML:-dpm}"
DAML="$(command -v "$DAML" 2>/dev/null || echo "$DAML")"
if [[ ! -x "${DAML}" ]]; then
  echo "error: cannot find dpm; set DAML=<dpm or damlc>" >&2
  exit 2
fi

# dpm trace runs as a dpm plugin; DPM_HOME, if set, is inherited, else dpm uses its own home.
DPM_BIN="${DPM_BIN:-dpm}"
if ! command -v "$DPM_BIN" >/dev/null 2>&1; then
  echo "error: cannot find dpm; set DPM_BIN" >&2
  exit 2
fi
run_trace() { "$DPM_BIN" trace "$@"; }

# Map failures into daml/Asset.daml, not only the test call site.
ASSET_SOURCES=(--daml-yaml "$HERE/unittests/daml.yaml" --daml-yaml "$HERE/daml.yaml" --dar "$HERE/.daml/dist/asset-1.0.0.dar")
# Script tests are a separate package on top of the asset DAR; rebuild both.
build_all() {
  local log
  log="$(cd "$HERE" && "$DAML" build --all 2>&1)" || { echo "$log" >&2; exit 2; }
}

rule() { printf '\n\033[1m=== %s ===\033[0m\n\n' "$1"; }

rule "1) Green run: all Daml Script unit tests pass (full transaction trees)"
build_all
run_trace test "$HERE/unittests" --files daml/Test.daml "${ASSET_SOURCES[@]}" --daml "$DAML" --color "$COLOR"

rule "2) Inject a regression: weaken 'ensure quantity > 0' to '>= 0' in daml/Asset.daml"
ASSET="$HERE/daml/Asset.daml"
cp "$ASSET" "$ASSET.bak"
trap 'mv -f "$ASSET.bak" "$ASSET" 2>/dev/null || true' EXIT
python3 - "$ASSET" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read().replace("ensure quantity > 0", "ensure quantity >= 0")
open(path, "w", encoding="utf-8").write(text)
PY
echo "patched daml/Asset.daml (the zero-quantity guard is now broken)"

rule "3) Red run: the guard test fails; dpm trace maps it to source and fails the build"
build_all
run_trace test "$HERE/unittests" --files daml/Test.daml "${ASSET_SOURCES[@]}" --daml "$DAML" --no-trees --color "$COLOR"
RED_EXIT=$?
echo
echo "CI gate exit code from the red run: ${RED_EXIT}  (non-zero => the CI job fails)"

rule "4) Revert the regression"
mv -f "$ASSET.bak" "$ASSET"
trap - EXIT
echo "restored daml/Asset.daml"
