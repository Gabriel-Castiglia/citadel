#!/bin/zsh
# paquete.sh - Builds the installer package build/Citadel-<version>.pkg.
# Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation. It is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.
#
# The package installs /Applications/Citadel.app. Its welcome, license and conclusion pages are
# in English and Spanish (instalador/resources/*.lproj); macOS Installer shows the language of
# the Mac. The package itself is not signed: that needs an Apple Developer ID.
set -euo pipefail
root=${0:A:h:h}
cd $root

$root/scripts/compilar.sh
$root/scripts/firma.sh $root/build/Citadel.app
export version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Citadel.app/Contents/Info.plist)
# Fills in @VERSION@ (the value goes through the environment, never through a sed pattern).
fill() { perl -pe 's/\@VERSION\@/$ENV{version}/g' "$1" > "$2" }

work=build/pkg
rm -rf $work
mkdir -p $work/root/Applications $work/resources
ditto build/Citadel.app $work/root/Applications/Citadel.app

# Never relocate: install to /Applications even if another copy is registered elsewhere.
pkgbuild --analyze --root $work/root $work/component.plist >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO $work/component.plist

pkgbuild --root $work/root --component-plist $work/component.plist \
  --identifier io.github.gabriel-castiglia.citadel.pkg --version $version \
  --install-location / --scripts instalador/scripts \
  $work/Citadel-component.pkg >/dev/null

for lang in en es; do
  mkdir -p $work/resources/$lang.lproj
  for f in instalador/resources/$lang.lproj/*; do
    fill $f $work/resources/$lang.lproj/${f:t}
  done
  cp LICENSE $work/resources/$lang.lproj/License.txt
done
fill instalador/Distribution.xml $work/Distribution.xml

out=build/Citadel-$version.pkg
productbuild --distribution $work/Distribution.xml --resources $work/resources \
  --package-path $work $out >/dev/null
rm -rf $work

# Remove the build copy from the app register, so Spotlight lists only the installed one.
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
$lsregister -u $root/build/Citadel.app 2>/dev/null || true
rm -rf build/Citadel.app

print "Built $root/$out"
(cd build && shasum -a 256 ${out:t})
