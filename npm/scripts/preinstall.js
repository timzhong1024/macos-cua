"use strict";

const { execFileSync } = require("node:child_process");

const minimumMajorVersion = 13;
const versionSource =
  process.env.MACOS_CUA_TEST_PRODUCT_VERSION ||
  readMacOSProductVersion();

if (!versionSource) {
  fail("Unable to determine the local macOS version.");
}

const majorVersion = parseMajorVersion(versionSource);
if (majorVersion === null) {
  fail(`Unrecognized macOS version string: ${JSON.stringify(versionSource)}`);
}

if (majorVersion < minimumMajorVersion) {
  fail(
    `macos-cua requires macOS ${minimumMajorVersion} or later; found macOS ${versionSource}.`
  );
}

function readMacOSProductVersion() {
  try {
    return execFileSync("sw_vers", ["-productVersion"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

function parseMajorVersion(version) {
  const match = /^(\d+)(?:\.\d+)?(?:\.\d+)?$/.exec(version);
  return match ? Number.parseInt(match[1], 10) : null;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
