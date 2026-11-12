#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
release_app="$project_dir/build/Build/Products/Release/LingoSphere.app"
debug_app="$project_dir/build/Build/Products/Debug/LingoSphere.app"
target_app="/Library/Input Methods/LingoSphere.app"
timestamp=$(/bin/date '+%Y%m%d-%H%M%S')
stage_app="/Library/Input Methods/.LingoSphere-stage-$timestamp.app"
source_app=""

for candidate in "$release_app" "$debug_app"; do
  if [[ -x "$candidate/Contents/MacOS/LingoSphere" ]]; then
    source_app="$candidate"
    break
  fi
done

if [[ -z "$source_app" ]]; then
  print -u2 "LingoSphere build not found. Build the Release scheme in Xcode first."
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$source_app"
if [[ "${1:-}" == "--check" ]]; then
  print "Installer preflight passed."
  print "Build selected: $source_app"
  print "Install target: $target_app"
  exit 0
fi

print "Administrator permission is required to install LingoSphere."
helper_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lingosphere-manual-install.XXXXXX")
helper="$helper_dir/input-source-migrator"
cleanup() {
  /bin/rm -rf "$helper_dir"
}
trap cleanup EXIT

/usr/bin/xcrun clang \
  -fobjc-arc -Os -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 \
  -framework Foundation -framework Carbon \
  "$script_dir/InputSourceMigrator.m" \
  -o "$helper"
/usr/bin/codesign --force --sign - "$helper"
/usr/bin/sudo /usr/bin/ditto "$source_app" "$stage_app"
/usr/bin/codesign --verify --deep --strict "$stage_app"

# Use the same ordered parent/child migration as the one-click package.
/usr/bin/sudo /usr/bin/env \
  LINGOSPHERE_INPUT_SOURCE_MIGRATOR="$helper" \
  /bin/bash "$script_dir/preinstall" unused "/Library/Input Methods"
backup_root=$(/usr/bin/sudo /bin/cat "/Library/Application Support/LingoSphere/pending-backup.txt")
if [[ -d "$target_app" ]]; then
  /usr/bin/sudo /bin/mv "$target_app" "$backup_root/LingoSphere-manual-replaced.app"
fi
/usr/bin/sudo /bin/mv "$stage_app" "$target_app"

/usr/bin/sudo /bin/bash "$script_dir/postinstall" unused "/Library/Input Methods"

print "LingoSphere has been installed."
print "Build used: $source_app"
print "Previous apps, when present, were backed up under /Library/Application Support/LingoSphere/backups."
print "Log out and sign back in once, then choose LingoSphere from the Input menu."
