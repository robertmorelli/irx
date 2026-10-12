#!/bin/bash
# Sanitized (ASan + UBSan) builds of the interpreters and large libraries whose regex engines are
# C/C++ code: CPython (re's _sre, and the regex module built against it), Perl (regexec.c), Ruby
# (Onigmo), Tcl (the ARE engine), ICU4C and Vectorscan. Same layout as tools/build_asan.sh; each
# takes several minutes. Usage: tools/build_asan_big.sh [python perl ruby tcl icu vectorscan]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); P=$ROOT/vendor/asan; SRC=$ROOT/vendor/src; H=$ROOT/hosts; B=/opt/homebrew/opt
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"; LSAN="-fsanitize=address,undefined"
mkdir -p "$P" "$SRC" "$H/bin"
fetch() { [ -d "$SRC/$2" ] || (cd "$SRC" && curl -sL "$1" | tar xz) ; }
stage() { local name=$1; shift; printf '%-10s ' "$name"; if ( set -e; "$@" ) >"/tmp/irx-asan-$name.log" 2>&1; then echo ok; else echo "FAILED (/tmp/irx-asan-$name.log)"; fi; }
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0

do_python() {
    V=3.14.8; fetch "https://www.python.org/ftp/python/$V/Python-$V.tgz" Python-$V
    cd "$SRC/Python-$V" && ./configure --prefix="$P/python" --with-address-sanitizer --with-undefined-behavior-sanitizer --without-pymalloc \
        --with-openssl="$B/openssl@3" >/dev/null && make -j8 && make install
    # The regex module, compiled with the sanitized interpreter's flags.
    "$P/python/bin/python3" -m pip install -q --no-binary regex regex
}
do_perl() {
    V=5.44.0; fetch "https://www.cpan.org/src/5.0/perl-$V.tar.gz" perl-$V
    cd "$SRC/perl-$V" && sh Configure -des -Dprefix="$P/perl" -Doptimize="-O1 -g" -Accflags="$SAN" -Aldflags="$LSAN" -Alddlflags="$LSAN" -Dman1dir=none -Dman3dir=none \
        && make -j8 && make install
}
do_ruby() {
    V=4.0.7; fetch "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-$V.tar.gz" ruby-$V
    cd "$SRC/ruby-$V" && ./configure --prefix="$P/ruby" --disable-install-doc --with-openssl-dir="$B/openssl@3" optflags="-O1" debugflags="-g" \
        CFLAGS="$SAN" LDFLAGS="$LSAN" && make -j8 && make install
}
do_tcl() {
    V=9.1.0; fetch "https://prdownloads.sourceforge.net/tcl/tcl$V-src.tar.gz" tcl$V
    cd "$SRC/tcl$V/unix" && ./configure --prefix="$P/tcl" CFLAGS="$SAN" LDFLAGS="$LSAN" && make -j8 && make install
}
do_icu() {
    V=78.3; fetch "https://github.com/unicode-org/icu/releases/download/release-$V/icu4c-$V-sources.tgz" icu
    cd "$SRC/icu/source" && CFLAGS="$SAN" CXXFLAGS="$SAN" LDFLAGS="$LSAN" ./runConfigureICU MacOSX --prefix="$P/icu" --enable-static --disable-shared \
        --disable-tests --disable-samples && make -j8 && make install
    cc $SAN -o "$H/bin/icu_host_asan" "$H/c/icu_host.c" -I"$P/icu/include" "$P/icu/lib/libicui18n.a" "$P/icu/lib/libicuuc.a" "$P/icu/lib/libicudata.a" -lc++
}
do_vectorscan() {
    V=$(brew list --versions vectorscan | awk '{print $2}'); fetch "https://github.com/VectorCamp/vectorscan/archive/refs/tags/vectorscan/$V.tar.gz" vectorscan-vectorscan-$V
    cd "$SRC/vectorscan-vectorscan-$V" && cmake -S . -B build-asan -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF \
        -DFAT_RUNTIME=OFF -DBUILD_UNIT=OFF -DBUILD_EXAMPLES=OFF -DBUILD_BENCHMARKS=OFF -DBUILD_TOOLS=OFF -DBOOST_ROOT="$B/boost" \
        -DCMAKE_C_FLAGS="$SAN" -DCMAKE_CXX_FLAGS="$SAN" -DCMAKE_INSTALL_PREFIX="$P/vectorscan" && cmake --build build-asan && cmake --install build-asan
    cc $SAN -o "$H/bin/hs_host_asan" "$H/c/hs_host.c" -I"$P/vectorscan/include" "$P/vectorscan/lib/libhs.a" -lc++
}

STAGES=${*:-python perl ruby tcl icu vectorscan}
for s in $STAGES; do stage "$s" "do_$s"; done
