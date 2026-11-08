#!/bin/bash
# Runs the core model checks (no XCTest or GUI needed).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
swift run --disable-sandbox --package-path "$root" DelayCoreChecks
