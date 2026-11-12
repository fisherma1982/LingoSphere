#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
derived_data="dist/XcodeDerivedData"

cd "${project_dir}"

xcrun swift scripts/build-menu-icon.swift

xcodebuild \
  -project Squirrel.xcodeproj \
  -scheme Squirrel \
  -configuration Release \
  -derivedDataPath "${derived_data}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

bash package/make_package "${derived_data}"

version=$(xcrun agvtool what-version | awk 'NF == 1 && $1 ~ /^[0-9.]+$/ { print $1; exit }')
output="dist/语界输入法-LingoSphere-v${version}-macOS15及以上-双击安装.pkg"
/bin/cp package/LingoSphere.pkg "${output}"

app="${derived_data}/Build/Products/Release/LingoSphere.app"
/usr/bin/codesign --verify --deep --strict "${app}"
/bin/test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Contents/Info.plist")" = "com.lingosphere.inputmethod.LingoSphere"
/bin/test "$(/usr/libexec/PlistBuddy -c 'Print :TISInputSourceID' "${app}/Contents/Info.plist")" = "com.lingosphere.inputmethod.LingoSphere"
/bin/test -f "${app}/Contents/Resources/LingoSphere.icns"
/bin/test -f "${app}/Contents/Resources/LingoSphereMenu.pdf"
/bin/test "$(/usr/bin/sips -g pixelWidth "${app}/Contents/Resources/LingoSphereMenu.pdf" \
  | /usr/bin/awk '/pixelWidth/ { print $2 }')" = "16.000"
/bin/test "$(/usr/bin/sips -g pixelHeight "${app}/Contents/Resources/LingoSphereMenu.pdf" \
  | /usr/bin/awk '/pixelHeight/ { print $2 }')" = "16.000"
/usr/bin/lipo -archs "${app}/Contents/MacOS/LingoSphere" | /usr/bin/grep -q 'arm64'
/usr/bin/lipo -archs "${app}/Contents/MacOS/LingoSphere" | /usr/bin/grep -q 'x86_64'
/usr/sbin/pkgutil --payload-files "${output}" \
  | /usr/bin/grep 'LingoSphere.app/Contents/MacOS/LingoSphere' >/dev/null
/usr/sbin/pkgutil --payload-files "${output}" \
  | /usr/bin/grep 'SharedSupport/candidate_translator/NOTICE.md' >/dev/null

# Verify what users actually receive, not only the Xcode build product. This
# catches lost generic-code signature xattrs (notably on rime-install).
expanded_package="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lingosphere-package-check.XXXXXX")"
cleanup() {
  /bin/rm -rf "${expanded_package}"
}
trap cleanup EXIT
/usr/sbin/pkgutil --expand-full "${output}" "${expanded_package}/expanded"
packaged_app="${expanded_package}/expanded/LingoSphere-component.pkg/Payload/LingoSphere.app"
/bin/test -d "${packaged_app}"
/usr/bin/cmp resources/LingoSphereMenu.pdf "${packaged_app}/Contents/Resources/LingoSphereMenu.pdf"
/usr/bin/codesign --verify --deep --strict "${packaged_app}"
/usr/bin/codesign --verify --strict "${packaged_app}/Contents/MacOS/rime-install"

print "安装包已生成：${project_dir}/${output}"
