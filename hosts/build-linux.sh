#!/bin/bash
# Linux (Fedora) counterpart of hosts/build.sh: build the native regex hosts into hosts/bin/ using
# distro packages found through pkg-config. hosts/build.sh stays the macOS/Homebrew script.
#
# Packages (Fedora 45):
#   sudo dnf install gcc gcc-c++ pkgconf-pkg-config pcre2-devel oniguruma-devel re2-devel \
#        libicu-devel boost-devel vectorscan-devel llvm-devel golang     # + rustup for hosts/rust
#   Script hosts: python3 ruby php-cli tcl perl; python-regex uses a venv at vendor/pyregex.
#
# Differences from the Mac build:
#   * cpp-regex is libstdc++'s std::regex here (libc++ on macOS): a different engine.
#   * libc-regex is glibc's regcomp/regexec (TRE-based libc on macOS): a different engine.
#   * Not built: swift/icu (Swift), jsc, java/re2j, dotnet, nim, racket, gawk/minrx (vendor/src),
#     and the ASan hosts (vendor/asan). Build those separately when needed.
set -e
H=$(cd "$(dirname "$0")" && pwd); mkdir -p "$H/bin"
LOG=$(mktemp -t irx-host-build.XXXXXX.log)
pc() { pkg-config "$@"; }
step() { printf '%-14s' "$1"; shift; if "$@" >"$LOG" 2>&1; then echo ok; else echo FAILED; tail -5 "$LOG"; fi; }
only() { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }   # ONLY="pcre2 re2" hosts/build-linux.sh

only pcre2       && step pcre2 sh -c "cc -O2 -o '$H/bin/pcre2_host' '$H/c/pcre2_host.c' \$(pkg-config --cflags --libs libpcre2-8)"
only oniguruma   && step oniguruma sh -c "cc -O2 -o '$H/bin/onig_host' '$H/c/onig_host.c' \$(pkg-config --cflags --libs oniguruma)"
only re2         && step re2 sh -c "c++ -O2 -std=c++17 -w -o '$H/bin/re2_host' '$H/c/re2_host.cc' \$(pkg-config --cflags --libs re2)"
only icu-c       && step icu-c sh -c "cc -O2 -o '$H/bin/icu_host' '$H/c/icu_host.c' \$(pkg-config --cflags --libs icu-i18n icu-uc)"
if pc --exists libpcre 2>/dev/null; then
only pcre1       && step pcre1 sh -c "cc -O2 -o '$H/bin/pcre1_host' '$H/c/pcre1_host.c' \$(pkg-config --cflags --libs libpcre)"
fi
only boost-regex && step boost-regex sh -c "c++ -O2 -std=c++17 -w -o '$H/bin/boost_regex_host' '$H/c/boost_regex_host.cc'"
only cpp-regex   && step cpp-regex sh -c "c++ -O2 -std=c++17 -w -o '$H/bin/cpp_regex_host' '$H/c/cpp_regex_host.cc'"
only libc-regex  && step libc-regex sh -c "c++ -O2 -std=c++17 -w -o '$H/bin/libc_regex_host' '$H/c/libc_regex_host.cc'"
HS=$(pc --exists libhs 2>/dev/null && echo libhs)
if [ -n "$HS" ]; then
only vectorscan  && step vectorscan sh -c "cc -O2 -o '$H/bin/hs_host' '$H/c/hs_host.c' \$(pkg-config --cflags --libs $HS) -lstdc++"
fi
L=$(command -v llvm-config || true)
if [ -n "$L" ]; then
only llvm-regex  && step llvm-regex sh -c "c++ -O2 -std=c++17 -w -o '$H/bin/llvm_host' '$H/c/llvm_host.cc' \$($L --cxxflags) \$($L --ldflags) \$($L --libs support demangle) \$($L --system-libs)"
fi
only go          && step go sh -c "cd '$H/go' && go build -o '$H/bin/go_host' ."
only rust        && step rust sh -c "cd '$H/rust' && cargo build --release -q && cp target/release/regex_host target/release/regex_lite_host target/release/automata_host target/release/fancy_host target/release/resharp_host target/release/regress_host '$H/bin/'"
# python-regex: the mrab `regex` module in a venv (targets/python-regex uses vendor/pyregex/bin/python).
only python-regex && step python-regex sh -c "[ -x '$H/../vendor/pyregex/bin/python' ] || python3 -m venv '$H/../vendor/pyregex'; '$H/../vendor/pyregex/bin/pip' install -q --upgrade regex"
rm -f "$LOG"
