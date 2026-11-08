#!/bin/zsh
# render.sh - Renders icono.svg to icono-1024.png with headless Chrome.
# Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation. It is distributed WITHOUT ANY WARRANTY; see
# the GNU General Public License for more details.
set -euo pipefail
here=${0:A:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
tmp=$(mktemp -d)
print -r -- "<html><body style='margin:0;background:transparent'><img src='file://$here/icono.svg' width=1024 height=1024></body></html>" > $tmp/icon.html
"$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --user-data-dir=$tmp/profile --window-size=1024,1024 --screenshot=$here/icono-1024.png "file://$tmp/icon.html" >/dev/null 2>&1
rm -rf $tmp
sips -g pixelWidth -g pixelHeight -g hasAlpha $here/icono-1024.png
