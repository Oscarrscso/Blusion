#!/usr/bin/env bash
# Line coverage for one Swift package (M1 acceptance: >= 90% for StremioKit).
#   ./scripts/coverage.sh StremioKit [threshold-percent]
# Works on macOS (xcrun llvm-cov) and Linux (llvm-cov from the Swift toolchain).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${1:?package name, e.g. StremioKit}"
THRESHOLD="${2:-90}"
DIR="$ROOT/Packages/$PKG"

LOG="$(mktemp)"
swift test --package-path "$DIR" --enable-code-coverage -Xswiftc -warnings-as-errors >"$LOG" 2>&1 || { cat "$LOG"; echo "coverage: tests failed" >&2; exit 1; }
rm -f "$LOG"
PROFDATA="$(swift test --package-path "$DIR" --show-codecov-path | sed 's/\.json$/.profdata/')"
[[ -f "$PROFDATA" ]] || PROFDATA="$(dirname "$(swift test --package-path "$DIR" --show-codecov-path)")/default.profdata"
BIN_DIR="$(swift build --package-path "$DIR" --show-bin-path)"
if [[ -d "$BIN_DIR/${PKG}PackageTests.xctest/Contents/MacOS" ]]; then
  BIN="$BIN_DIR/${PKG}PackageTests.xctest/Contents/MacOS/${PKG}PackageTests"
else
  BIN="$BIN_DIR/${PKG}PackageTests.xctest"
fi
LLVM_COV=(llvm-cov); command -v llvm-cov >/dev/null 2>&1 || LLVM_COV=(xcrun llvm-cov)

# Sources only: exclude tests and checkouts.
"${LLVM_COV[@]}" report "$BIN" -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(\.build|Tests|/usr/)' | tee "$ROOT/coverage-$PKG.txt" | tail -n 40

PCT="$("${LLVM_COV[@]}" export "$BIN" -instr-profile "$PROFDATA" -summary-only \
  -ignore-filename-regex='(\.build|Tests|/usr/)' | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%.2f" % d["data"][0]["totals"]["lines"]["percent"])')"
echo "coverage: $PKG lines = ${PCT}% (threshold ${THRESHOLD}%)"
python3 -c "import sys; sys.exit(0 if float('$PCT') >= float('$THRESHOLD') else 1)" || { echo "coverage below threshold" >&2; exit 1; }
