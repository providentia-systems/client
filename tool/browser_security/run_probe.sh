#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/browser-security-proof
dart compile js tool/browser_security/probe.dart -o build/browser-security-proof/probe.js
cp web/sqlite3.wasm build/browser-security-proof/
printf '<!doctype html><html><body><script src="probe.js"></script></body></html>' > build/browser-security-proof/index.html
node tool/browser_security/run_probe.mjs
