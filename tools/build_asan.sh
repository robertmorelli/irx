#!/bin/bash
# Build ASan/UBSan static libraries of PCRE2 and Oniguruma into vendor/asan (sources from their
# GitHub releases, matching the Homebrew versions), for the *-asan targets.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); P=$ROOT/vendor/asan; SRC=$ROOT/vendor/src
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"
mkdir -p "$P" "$SRC"; cd "$SRC"
V=$(pcre2-config --version); O=$(pkg-config --modversion oniguruma)
[ -d pcre2-$V ] || { curl -sL "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$V/pcre2-$V.tar.gz" | tar xz; }
[ -d onig-$O ] || { curl -sL "https://github.com/kkos/oniguruma/releases/download/v$O/onig-$O.tar.gz" | tar xz; }
(cd pcre2-$V && ./configure --prefix="$P" --disable-shared --enable-static --enable-jit CFLAGS="$SAN" LDFLAGS="-fsanitize=address,undefined" >/dev/null && make -j8 >/dev/null && make install >/dev/null)
(cd onig-$O && ./configure --prefix="$P" --disable-shared --enable-static CFLAGS="$SAN" LDFLAGS="-fsanitize=address,undefined" >/dev/null && make -j8 >/dev/null && make install >/dev/null)
echo "built into $P"
