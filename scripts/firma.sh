#!/bin/zsh
# firma.sh - Signs build/Citadel.app with a stable self-signed certificate.
#
# The first run creates the certificate "Citadel (local signing)" in its own keychain
# (~/Library/Keychains/citadel-signing.keychain-db). That keychain's password lives in
# the login keychain under the service "citadel-local-signing". Every later run reuses
# the same certificate, so the signature (and macOS permissions) stay the same.
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
root=${0:A:h:h}
app=${1:-$root/build/Citadel.app}
name="Citadel (local signing)"
service="citadel-local-signing"
keychain=$HOME/Library/Keychains/citadel-signing.keychain-db
openssl=/usr/bin/openssl

[[ -d $app ]] || { print -u2 "Not found: $app (run scripts/compilar.sh first)"; exit 1 }

# 1. Keychain password, kept in the login keychain.
if ! password=$(security find-generic-password -a "$USER" -s $service -w 2>/dev/null); then
  password=$($openssl rand -hex 24)
  security add-generic-password -a "$USER" -s $service -l "Citadel signing keychain" -w "$password" -U
  print "Stored the signing keychain password in the login keychain ($service)."
fi

# 2. The signing keychain itself.
if [[ ! -f $keychain ]]; then
  security create-keychain -p "$password" $keychain
  security set-keychain-settings $keychain   # no auto-lock timeout
  print "Created $keychain"
fi
security unlock-keychain -p "$password" $keychain

# Keep it in the user search list so codesign can build the certificate chain.
current=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
if (( ! ${current[(Ie)$keychain]} )); then
  security list-keychains -d user -s "${current[@]}" $keychain
fi

# 3. The certificate, created once.
if ! security find-certificate -c "$name" $keychain >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  trap 'rm -rf $tmp' EXIT
  cat > $tmp/cert.cnf <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $name
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
  $openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout $tmp/key.pem -out $tmp/cert.pem -config $tmp/cert.cnf 2>/dev/null
  p12pass=$($openssl rand -hex 16)
  $openssl pkcs12 -export -inkey $tmp/key.pem -in $tmp/cert.pem -name "$name" \
    -out $tmp/id.p12 -passout pass:$p12pass
  security import $tmp/id.p12 -k $keychain -P $p12pass -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" $keychain >/dev/null
  print "Created the certificate \"$name\"."
fi

# 4. Sign with the certificate's SHA-1, so there is never any ambiguity.
hash=$(security find-certificate -c "$name" -Z $keychain | awk '/SHA-1 hash:/ {print $NF; exit}')
[[ -n $hash ]] || { print -u2 "Certificate \"$name\" not found in $keychain"; exit 1 }
codesign --force --deep --keychain $keychain --sign $hash --timestamp=none \
  --identifier io.github.gabriel-castiglia.citadel $app
codesign --verify --verbose=1 $app 2>&1 | sed 's/^/  /' || true
print "Signed $app with \"$name\" ($hash)"
