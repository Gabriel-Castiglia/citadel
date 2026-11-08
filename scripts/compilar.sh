#!/bin/zsh
# compilar.sh - Builds build/Citadel.app with swiftc (no Xcode needed).
# Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation. It is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.
set -euo pipefail

# The version lives here and only here; the app reads it from Info.plist.
version=1.0.0

root=${0:A:h:h}
cd $root

app=build/Citadel.app
contents=$app/Contents
rm -rf $app build/Citadel.iconset
mkdir -p $contents/MacOS $contents/Resources

print "Compiling…"
swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos14.0 \
  -module-name Citadel \
  Sources/*.swift \
  -o $contents/MacOS/Citadel

print "Making the icon…"
iconset=build/Citadel.iconset
mkdir -p $iconset
src=icono/icono-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size $src --out $iconset/icon_${size}x${size}.png >/dev/null
  double=$((size * 2))
  sips -z $double $double $src --out $iconset/icon_${size}x${size}@2x.png >/dev/null
done
iconutil -c icns -o $contents/Resources/Citadel.icns $iconset
rm -rf $iconset

cat > $contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Citadel</string>
  <key>CFBundleDisplayName</key><string>Citadel</string>
  <key>CFBundleExecutable</key><string>Citadel</string>
  <key>CFBundleIdentifier</key><string>io.github.gabriel-castiglia.citadel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleIconFile</key><string>Citadel</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>es</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Gabriel Castiglia. GNU GPL, version 2 only.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
print -n "APPL????" > $contents/PkgInfo
plutil -lint $contents/Info.plist >/dev/null
print "Built $root/$app ($version)"
