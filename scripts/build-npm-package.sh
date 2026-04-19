#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}/npm"
BIN_DIR="${PACKAGE_DIR}/bin"
OUTPUT_BIN="${BIN_DIR}/macos-cua"
ARM64_BUILD_DIR="${ROOT_DIR}/.build-npm-arm64"
X64_BUILD_DIR="${ROOT_DIR}/.build-npm-x86_64"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macos-cua npm packaging currently requires macOS" >&2
  exit 1
fi

pushd "${ROOT_DIR}" >/dev/null
swift build -c release --arch arm64 --product macos-cua --build-path "${ARM64_BUILD_DIR}"
swift build -c release --arch x86_64 --product macos-cua --build-path "${X64_BUILD_DIR}"
popd >/dev/null

mkdir -p "${BIN_DIR}"
lipo -create \
  "${ARM64_BUILD_DIR}/release/macos-cua" \
  "${X64_BUILD_DIR}/release/macos-cua" \
  -output "${OUTPUT_BIN}"
chmod 755 "${OUTPUT_BIN}"
install -m 644 "${ROOT_DIR}/LICENSE" "${PACKAGE_DIR}/LICENSE"

echo "staged npm package binary at ${OUTPUT_BIN}"
