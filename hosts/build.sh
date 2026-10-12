#!/bin/bash
# Build every native regex host into hosts/bin/. Script hosts (Python, Ruby, PHP, Tcl,
# Racket, Emacs) run from source; JS runtimes use driver.js directly.
set -e
H=$(cd "$(dirname "$0")" && pwd); B=/opt/homebrew/opt; mkdir -p "$H/bin"
step() { printf '%-14s' "$1"; shift; if "$@" >/tmp/irx-host-build.log 2>&1; then echo ok; else echo FAILED; tail -5 /tmp/irx-host-build.log; fi; }
step pcre2 cc -O2 -o "$H/bin/pcre2_host" "$H/c/pcre2_host.c" -I$B/pcre2/include -L$B/pcre2/lib -lpcre2-8
step oniguruma cc -O2 -o "$H/bin/onig_host" "$H/c/onig_host.c" -I$B/oniguruma/include -L$B/oniguruma/lib -lonig
step re2 sh -c "c++ -O2 -std=c++17 -Wno-everything -o '$H/bin/re2_host' '$H/c/re2_host.cc' \$(pkg-config --cflags --libs re2)"
step vectorscan cc -O2 -o "$H/bin/hs_host" "$H/c/hs_host.c" -I$B/vectorscan/include -L$B/vectorscan/lib -lhs -lstdc++
L=$B/llvm/bin/llvm-config
step llvm-regex sh -c "c++ -O2 -std=c++17 -Wno-everything -o '$H/bin/llvm_host' '$H/c/llvm_host.cc' \$($L --cxxflags) \$($L --ldflags) -lLLVMSupport -lLLVMDemangle \$($L --system-libs)"
step go sh -c "cd '$H/go' && go build -o '$H/bin/go_host' ."
step rust sh -c "cd '$H/rust' && cargo build --release -q && cp target/release/regex_host target/release/regex_lite_host target/release/fancy_host target/release/resharp_host '$H/bin/'"
step java sh -c "javac -d '$H/bin/java' '$H/java/Host.java'"
step dotnet sh -c "cd '$H/dotnet' && dotnet build -c Release -o '$H/bin/dotnet' -v q"
step swift swiftc -O -o "$H/bin/swift_host" "$H/swift/host.swift"
step nim sh -c "cd '$H/nim' && nim c -d:release --hints:off --verbosity:0 -o:'$H/bin/nim_host' host.nim"
step racket raco make "$H/racket/host.rkt"
