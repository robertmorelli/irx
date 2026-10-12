#!/bin/bash
# Build gawk's support library (GNU regex, MinRX) into vendor/src/gawk-<v>/support/libsupport.a for
# the gnu-regex and minrx targets. pma is disabled so the regex code uses plain malloc.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); V=${GAWK_VERSION:-5.4.1}; mkdir -p "$ROOT/vendor/src"; cd "$ROOT/vendor/src"
[ -d gawk-$V ] || curl -sL "https://ftp.gnu.org/gnu/gawk/gawk-$V.tar.gz" | tar xz
cd gawk-$V && ./configure --disable-nls --disable-pma >/dev/null && make -j8 -C support >/dev/null && echo "built $PWD/support/libsupport.a"
