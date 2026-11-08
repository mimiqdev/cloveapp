#!/bin/sh
# Generate Clove.xcodeproj from project.yml.
#
# The generated project is gitignored. The development team comes from the
# optional Config/Local.xcconfig include in Config/Shared.xcconfig, so no team
# ID is ever written into the repository.
set -eu
cd "$(dirname "$0")/.."
exec xcodegen generate
