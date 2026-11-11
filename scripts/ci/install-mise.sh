#!/usr/bin/env bash
# Install the pinned mise release on a macOS arm64 CI runner, check it against
# its published SHA-256, then install the tools mise.lock pins (XcodeGen).
#
# To update: pick a release from https://github.com/jdx/mise/releases and copy
# the mise-v<version>-macos-arm64 line from its SHASUMS256.txt.
set -euo pipefail
cd "$(dirname "$0")/../.."

version="2026.11.6"
sha256="8b9b3459f331bde1e7b830d829dddd7cda5a558063103e451fba9f976e91acdb"

if [ "$(uname -s)-$(uname -m)" != "Darwin-arm64" ]; then
    echo "error: the pinned mise is for macOS arm64, not $(uname -s)-$(uname -m)" >&2
    exit 1
fi

bin_dir="${RUNNER_TEMP:?RUNNER_TEMP is not set; this script is for CI runners}/mise-bin"
mkdir -p "$bin_dir"
curl --fail --silent --show-error --location --retry 3 \
    --output "$bin_dir/mise" \
    "https://github.com/jdx/mise/releases/download/v$version/mise-v$version-macos-arm64"
echo "$sha256  $bin_dir/mise" | shasum -a 256 --check --status || {
    echo "error: the mise download does not match its pinned SHA-256" >&2
    exit 1
}
chmod +x "$bin_dir/mise"
if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$bin_dir" >>"$GITHUB_PATH"
fi

"$bin_dir/mise" --version
"$bin_dir/mise" trust --quiet
"$bin_dir/mise" install
"$bin_dir/mise" exec -- xcodegen --version
