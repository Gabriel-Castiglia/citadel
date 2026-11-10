#!/bin/zsh
# render-accents.sh - Renders the icon once per theme colour (icono/accents/<key>.png, 512 px).
# Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation. It is distributed WITHOUT ANY WARRANTY; see
# the GNU General Public License for more details.
#
# Only the glow behind the citadel changes: its two greens (#3ccf75, #2a9d57) become the bright
# and the deep tone of each colour. Keep the keys and tones in sync with Sources/Theme.swift.
set -euo pipefail
here=${0:A:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p $here/accents
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
typeset -A tones
tones=(green "3ccf75 2a9d57" gold "e2b84c 9a6f00" purple "b392e0 5b2a86" sky "5cb8f0 1a8cd8" ember "f08a5d d9652f"
       red "f2545b c8102e" yellow "f5c842 b88a00" teal "4db6ac 00796b" blue "6e9bff 1f5fd1" pink "f06292 c2185b"
       black "8e8e93 3a3a3c" white "ffffff c7c7cc")
for key in ${(k)tones}; do
    # the tones go through the environment, never into a substitution pattern
    BRIGHT=${${=tones[$key]}[1]} DEEP=${${=tones[$key]}[2]} \
        perl -pe 's/#3ccf75/#$ENV{BRIGHT}/g; s/#2a9d57/#$ENV{DEEP}/g' $here/icono.svg > $tmp/$key.svg
    print -r -- "<html><body style='margin:0;background:transparent'><img src='file://$tmp/$key.svg' width=1024 height=1024></body></html>" > $tmp/$key.html
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
      --user-data-dir=$tmp/profile --window-size=1024,1024 --screenshot=$tmp/$key.png "file://$tmp/$key.html" >/dev/null 2>&1
    sips -z 512 512 $tmp/$key.png --out $here/accents/$key.png >/dev/null
done
ls $here/accents
