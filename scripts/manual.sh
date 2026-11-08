#!/bin/zsh
# manual.sh - Builds the PDF manuals from the READMEs.
#   README.md     -> docs/Citadel-manual-en.pdf
#   README.es.md  -> docs/Citadel-manual-es.pdf
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
# Requires pandoc (brew install pandoc) and Google Chrome, which prints the HTML to PDF.
# Run it again after every change to either README or to the images in docs/images.
set -euo pipefail
root=${0:A:h:h}
cd $root

repo="https://github.com/Gabriel-Castiglia/citadel"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
version=$(sed -n 's/^version=//p' scripts/compilar.sh | head -1)

command -v pandoc >/dev/null || { print -u2 "pandoc is missing: brew install pandoc"; exit 1 }
[[ -x $chrome ]] || { print -u2 "Google Chrome is missing from /Applications"; exit 1 }
[[ -n $version ]] || { print -u2 "No version found in scripts/compilar.sh"; exit 1 }

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT

# Relative links (LICENSE, CHANGELOG.md, docs/…) point to the repository in the PDF; otherwise they
# would become paths inside the temporary folder of whoever builds it.
cat > $tmp/links.lua <<LUA
function Link(el)
  if not el.target:match("^%a[%w+.-]*:") and not el.target:match("^#") then
    el.target = "$repo/blob/main/" .. el.target
  end
  return el
end
LUA

build() {
    local source=$1 lang=$2 title=$3 subtitle=$4 output=$5
    # Cover block with the icon, the name, the version and the repository.
    cat > $tmp/cover-$lang.html <<HTML
<div class="cover">
  <img src="icono/icono-1024.png" alt="">
  <div>
    <p class="name">Citadel</p>
    <p class="subtitle">$subtitle $version · <a href="$repo">${repo#https://}</a></p>
  </div>
</div>
HTML
    # Self-contained HTML: stylesheet and images embedded, no references to local files.
    pandoc $source --from gfm --to html5 --standalone --embed-resources \
        --lua-filter $tmp/links.lua \
        --css docs/manual.css \
        --include-before-body $tmp/cover-$lang.html \
        --metadata pagetitle="$title" \
        --metadata lang=$lang \
        --output $tmp/manual-$lang.html
    # No header or footer: Chrome would print the local path of the HTML file in them.
    "$chrome" --headless --disable-gpu --no-pdf-header-footer \
        --print-to-pdf=$root/$output "file://$tmp/manual-$lang.html" 2>/dev/null
    print "Manual: $output"
}

build README.md    en "Citadel · Manual"            "Local AI chat for macOS · version"     docs/Citadel-manual-en.pdf
build README.es.md es "Citadel · Manual de usuario" "Chat con IA local para macOS · versión" docs/Citadel-manual-es.pdf
