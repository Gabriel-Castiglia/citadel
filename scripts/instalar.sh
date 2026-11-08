#!/bin/zsh
# instalar.sh - Builds, signs and installs Citadel in /Applications.
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
here=${0:A:h}
root=${here:h}
target=/Applications/Citadel.app

$here/compilar.sh
$here/firma.sh $root/build/Citadel.app

# Quit a running copy before replacing it.
if pgrep -xq Citadel; then
  osascript -e 'tell application id "io.github.gabriel-castiglia.citadel" to quit' >/dev/null 2>&1 || true
  sleep 1
fi
rm -rf $target
ditto $root/build/Citadel.app $target
codesign --verify $target

# Remove the build copy, so Spotlight and Launchpad list Citadel only once.
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
$lsregister -u $root/build/Citadel.app 2>/dev/null || true
rm -rf $root/build/Citadel.app
print "Installed $target"
codesign -d -r- $target 2>&1 | grep designated
