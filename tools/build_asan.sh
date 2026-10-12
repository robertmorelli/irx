#!/bin/bash
# Sanitized (ASan + UBSan) builds of the engines whose regex code is compiled C, C++ or Rust,
# for the *-asan targets. Libraries go to vendor/asan, hosts to hosts/bin/*_asan, sources to
# vendor/src. Usage: tools/build_asan.sh [stage ...]   (default: every stage)
#   pcre2 onig  - PCRE2 and Oniguruma (Homebrew versions, from their releases)
#   pcre1       - PCRE1 8.45
#   re2         - RE2 (Homebrew version) against Homebrew abseil
#   gawk        - gawk's support library (GNU regex, MinRX)
#   llvm        - LLVM's Spencer regex sources (Homebrew LLVM version)
#   quickjs     - QuickJS (upstream source)
#   nim         - nim-regex (the nim host compiled through C with sanitizers)
#   rust        - regex, regex-lite, regex-automata, fancy-regex, RE# (nightly -Zsanitizer=address)
#   boost cpp   - Boost.Regex and libc++ std::regex (header-only: the host build instruments them)
#   python perl ruby tcl icu vectorscan - interpreters and large libraries (tools/build_asan_big.sh)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); P=$ROOT/vendor/asan; SRC=$ROOT/vendor/src; H=$ROOT/hosts; B=/opt/homebrew/opt
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"; LSAN="-fsanitize=address,undefined"
mkdir -p "$P" "$SRC" "$H/bin"
fetch() { [ -d "$SRC/$2" ] || (cd "$SRC" && curl -sL "$1" | tar xz) ; }
stage() { local name=$1; shift; printf '%-10s ' "$name"; if ( set -e; "$@" ) >"/tmp/irx-asan-$name.log" 2>&1; then echo ok; else echo "FAILED (/tmp/irx-asan-$name.log)"; fi; }

do_pcre2() {
    V=$(pcre2-config --version); fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$V/pcre2-$V.tar.gz" pcre2-$V
    cd "$SRC/pcre2-$V" && ./configure --prefix="$P" --disable-shared --enable-static --enable-jit CFLAGS="$SAN" LDFLAGS="$LSAN" && make -j8 && make install
    cc $SAN -o "$H/bin/pcre2_host_asan" "$H/c/pcre2_host.c" -I"$P/include" "$P/lib/libpcre2-8.a"
}
do_onig() {
    V=$(pkg-config --modversion oniguruma); fetch "https://github.com/kkos/oniguruma/releases/download/v$V/onig-$V.tar.gz" onig-$V
    cd "$SRC/onig-$V" && ./configure --prefix="$P" --disable-shared --enable-static CFLAGS="$SAN" LDFLAGS="$LSAN" && make -j8 && make install
    cc $SAN -o "$H/bin/onig_host_asan" "$H/c/onig_host.c" -I"$P/include" "$P/lib/libonig.a"
}
do_pcre1() {
    fetch "https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz/download" pcre-8.45
    cd "$SRC/pcre-8.45" && ./configure --prefix="$P/pcre1" --disable-shared --enable-static --enable-utf --enable-unicode-properties --enable-jit --disable-cpp CFLAGS="$SAN" LDFLAGS="$LSAN" && make -j8 && make install
    cc $SAN -o "$H/bin/pcre1_host_asan" "$H/c/pcre1_host.c" -I"$P/pcre1/include" "$P/pcre1/lib/libpcre.a"
}
do_re2() {
    # abseil from source with the same flags: sanitizer builds of its headers change hash-table
    # layouts (generation checks), so a prebuilt abseil would not match.
    AV=$(brew list --versions abseil | awk '{print $2}' | sed 's/_.*//'); fetch "https://github.com/abseil/abseil-cpp/archive/refs/tags/$AV.tar.gz" abseil-cpp-$AV
    (cd "$SRC/abseil-cpp-$AV" && cmake -S . -B build-asan -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_SHARED_LIBS=OFF -DABSL_PROPAGATE_CXX_STD=ON \
        -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_FLAGS="$SAN" -DCMAKE_INSTALL_PREFIX="$P/absl" && cmake --build build-asan && cmake --install build-asan)
    V=$(brew list --versions re2 | awk '{print $2}' | sed 's/_.*//'); fetch "https://github.com/google/re2/archive/refs/tags/$V.tar.gz" re2-$V
    cd "$SRC/re2-$V" && rm -rf build-asan && cmake -S . -B build-asan -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_SHARED_LIBS=OFF -DRE2_BUILD_TESTING=OFF \
        -DCMAKE_PREFIX_PATH="$P/absl" -DCMAKE_INSTALL_PREFIX="$P/re2" -DCMAKE_CXX_FLAGS="$SAN" && cmake --build build-asan && cmake --install build-asan
    c++ $SAN -std=c++17 -Wno-everything -o "$H/bin/re2_host_asan" "$H/c/re2_host.cc" -I"$P/re2/include" \
        $(PKG_CONFIG_PATH="$P/re2/lib/pkgconfig:$P/absl/lib/pkgconfig" pkg-config --cflags --libs --static re2) -framework CoreFoundation
}
do_gawk() {
    V=5.4.1; fetch "https://ftp.gnu.org/gnu/gawk/gawk-$V.tar.gz" gawk-$V
    rm -rf "$SRC/gawk-$V-asan"; cp -R "$SRC/gawk-$V" "$SRC/gawk-$V-asan"
    cd "$SRC/gawk-$V-asan" && ./configure --disable-nls --disable-pma CFLAGS="$SAN" LDFLAGS="$LSAN" && make -C support clean && make -j8 -C support
    G="$SRC/gawk-$V-asan/support"
    c++ $SAN -std=c++17 -Wno-everything -I"$G" -I"$G/.." -o "$H/bin/gnu_regex_host_asan" "$H/c/gnu_regex_host.cc" "$G/libsupport.a"
    c++ $SAN -std=c++17 -Wno-everything -I"$G" -o "$H/bin/minrx_host_asan" "$H/c/minrx_host.cc" "$G/libsupport.a"
}
do_llvm() {
    V=$($B/llvm/bin/llvm-config --version); D="$SRC/llvm-regex-$V"; mkdir -p "$D/llvm/Support"
    U="https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-$V/llvm"
    for f in regcomp.c regengine.inc regexec.c regfree.c regerror.c regstrlcpy.c regutils.h regex2.h Regex.cpp; do [ -f "$D/$f" ] || curl -sfL -o "$D/$f" "$U/lib/Support/$f"; done
    [ -f "$D/llvm/Support/regex_impl.h" ] || curl -sfL -o "$D/llvm/Support/regex_impl.h" "$U/lib/Support/regex_impl.h" || curl -sfL -o "$D/llvm/Support/regex_impl.h" "$U/include/llvm/Support/regex_impl.h"
    cp "$D/llvm/Support/regex_impl.h" "$D/regex_impl.h"
    # regcomp.c includes LLVM's private build config; the regex code needs nothing from it.
    mkdir -p "$D/llvm/Config"; [ -f "$D/llvm/Config/config.h" ] || : > "$D/llvm/Config/config.h"
    cd "$D"; rm -f ./*.o
    for f in regcomp regexec regfree regerror regstrlcpy; do cc $SAN -I. -I"$($B/llvm/bin/llvm-config --includedir)" -c $f.c -o $f.o || return 1; done
    c++ $SAN -std=c++17 -I. $($B/llvm/bin/llvm-config --cxxflags) -fno-exceptions -c Regex.cpp -o Regex.o
    c++ $SAN -std=c++17 -Wno-everything -o "$H/bin/llvm_host_asan" "$H/c/llvm_host.cc" "$D"/*.o $($B/llvm/bin/llvm-config --cxxflags) \
        $($B/llvm/bin/llvm-config --ldflags) -lLLVMSupport -lLLVMDemangle $($B/llvm/bin/llvm-config --system-libs)
}
do_quickjs() {
    Q="$SRC/quickjs-asan"; [ -d "$Q" ] || git clone -q https://github.com/bellard/quickjs "$Q"
    cd "$Q" && make clean >/dev/null 2>&1; make -j8 CONFIG_ASAN=y qjs && mkdir -p "$ROOT/vendor/quickjs-asan/bin" && cp qjs "$ROOT/vendor/quickjs-asan/bin/qjs"
}
do_nim() {
    cd "$H/nim" && nim c -d:release --hints:off --verbosity:0 --nimcache:"$SRC/nimcache-asan" --passC:"$SAN" --passL:"$LSAN" -o:"$H/bin/nim_host_asan" host.nim
}
do_rust() {
    # Homebrew's stable rustc/cargo can shadow rustup's proxies: use the nightly binaries directly.
    local NC NR; NC=$(rustup which --toolchain nightly cargo); NR=$(rustup which --toolchain nightly rustc)
    cd "$H/rust" && RUSTC="$NR" RUSTFLAGS="-Zsanitizer=address" "$NC" build --release --target aarch64-apple-darwin --target-dir target-asan
    for b in regex_host regex_lite_host automata_host fancy_host resharp_host; do cp "target-asan/aarch64-apple-darwin/release/$b" "$H/bin/${b}_asan"; done
}
do_boost() { c++ $SAN -std=c++17 -Wno-everything -I"$B/boost/include" -o "$H/bin/boost_regex_host_asan" "$H/c/boost_regex_host.cc"; }
do_cpp() { c++ $SAN -std=c++17 -Wno-everything -o "$H/bin/cpp_regex_host_asan" "$H/c/cpp_regex_host.cc"; }

STAGES=${*:-pcre2 onig pcre1 re2 gawk llvm quickjs nim rust boost cpp}
for s in $STAGES; do stage "$s" "do_$s"; done
