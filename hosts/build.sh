#!/bin/bash
# Build the native regex hosts into hosts/bin/.
set -e
H=$(cd "$(dirname "$0")" && pwd); B=/opt/homebrew/opt; mkdir -p "$H/bin"
cc -O2 -o "$H/bin/pcre2_host" "$H/c/pcre2_host.c" -I$B/pcre2/include -L$B/pcre2/lib -lpcre2-8
cc -O2 -o "$H/bin/onig_host" "$H/c/onig_host.c" -I$B/oniguruma/include -L$B/oniguruma/lib -lonig
c++ -O2 -std=c++17 -Wno-everything -o "$H/bin/re2_host" "$H/c/re2_host.cc" $(pkg-config --cflags --libs re2)
(cd "$H/go" && go build -o "$H/bin/go_host" .)
(cd "$H/rust" && cargo build --release -q && cp target/release/regex_host target/release/fancy_host "$H/bin/")
echo "built: $(ls "$H/bin" | tr '\n' ' ')"
