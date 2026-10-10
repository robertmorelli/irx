#!/bin/bash
# 1-minute smoke campaign on every engine branch. Resumable: skips branches whose
# findings/1m-<name>/summary.json exists. Usage: tools/campaign1m.sh [names...]
set -u
R=$(cd "$(dirname "$0")/.." && pwd); cd "$R"
J=$R/vendor/jsvu-home/.jsvu/bin; PY=/opt/homebrew/bin/python3; H=$R/hosts/bin
NOLOOK='\n[weights]\nlookahead = 0\nneg_lookahead = 0\nlookbehind = 0\nneg_lookbehind = 0\n'
NOLB='\n[weights]\nlookbehind = 0\nneg_lookbehind = 0\n'
NOERE='\n[weights]\nlookahead = 0\nneg_lookahead = 0\nlookbehind = 0\nneg_lookbehind = 0\nlazy = 0\nbackslash_b = 0\nbackslash_B = 0\n'
S=$R/hosts/script
NOV='\n[flags]\nsets = ["", "i", "m", "s", "u", "iu", "im", "is", "ms", "ims", "imu", "isu", "msu", "imsu", "su", "mu"]\n'
DUR=${DUR:-60}
# name | engine args | extra toml
TARGETS=(
  "main|--d8 /opt/homebrew/bin/d8|"
  "perl|--perl /opt/homebrew/bin/perl|"
  "quickjs|--shell /opt/homebrew/bin/qjs@--std@{driver}@{mode}|"
  "xs|--shell $PY@$R/tools/bridge.py@$J/xs@{driver}@{mode}|"
  "boa|--shell $PY@$R/tools/bridge.py@$R/vendor/boa/bin/boa@{driver}@{mode}|"
  "engine262|--shell $PY@$R/tools/bridge.py@$R/vendor/node/node_modules/.bin/engine262@{driver}@{mode} --no-selfcheck|"
  "hermes|--shell $PY@$R/tools/bridge.py@$J/hermes@{driver}@{mode} --no-selfcheck|$NOV"
  "pcre2|--shell $H/pcre2_host@{mode} --dialect perl|"
  "oniguruma|--shell $H/onig_host@{mode} --dialect perl|"
  "re2|--shell $H/re2_host@{mode} --dialect perl|$NOLOOK"
  "go-regexp|--shell $H/go_host@{mode} --dialect perl|$NOLOOK"
  "rust-regex|--shell $H/regex_host@{mode} --dialect perl|$NOLOOK"
  "fancy-regex|--shell $H/fancy_host@{mode} --dialect perl|"
  "python-re|--shell $PY@$S/py_host.py@{mode} --dialect perl|"
  "ruby-onigmo|--shell /opt/homebrew/bin/ruby@$S/rb_host.rb@{mode} --dialect perl|"
  "php-pcre2|--shell /opt/homebrew/bin/php@$S/php_host.php@{mode} --dialect perl|"
  "tcl|--shell /opt/homebrew/bin/tclsh@$S/tcl_host.tcl@{mode} --dialect perl|$NOLB"
  "java|--shell /usr/bin/java@-cp@$H/java@Host@{mode} --dialect perl|"
  "dotnet-interp|--shell $H/dotnet/host@interp@{mode} --dialect perl|"
  "dotnet-compiled|--shell $H/dotnet/host@compiled@{mode} --dialect perl|"
  "dotnet-nonbacktracking|--shell $H/dotnet/host@nonbacktracking@{mode} --dialect perl|$NOLOOK"
  "swift-regex|--shell $H/swift_host@swift@{mode} --dialect perl|$NOLB"
  "icu|--shell $H/swift_host@icu@{mode} --dialect perl|"
  "nim-regex|--shell $H/nim_host@{mode} --dialect perl|"
  "racket|--shell /opt/homebrew/bin/racket@$R/hosts/racket/host.rkt@{mode} --dialect perl|"
  "emacs|--shell /opt/homebrew/bin/emacs@-Q@--batch@-l@$R/hosts/emacs/host.el@{mode} --dialect perl|$NOLOOK"
  "node|--shell /usr/local/bin/node@{driver}@{mode}|"
  "bun|--shell /opt/homebrew/bin/bun@{driver}@{mode}|"
  "deno|--shell /opt/homebrew/bin/deno@run@-q@{driver}@{mode}|"
  "vectorscan|--shell $H/hs_host@{mode} --dialect perl|$NOLOOK"
  "llvm-regex|--shell $H/llvm_host@{mode} --dialect perl|$NOERE"
  "resharp|--shell $H/resharp_host@{mode} --dialect perl|"
)
want=" ${*:-} "
for t in "${TARGETS[@]}"; do
  IFS='|' read -r name args extra <<<"$t"
  [ "$want" != "  " ] && [[ "$want" != *" $name "* ]] && continue
  out="findings/1m-$name"
  if [ -f "$out/summary.json" ]; then echo "$name: done, skipping"; continue; fi
  git rev-parse -q --verify "$name" >/dev/null || git branch "$name" main
  git checkout -q "$name" && git merge -q --no-edit main >/dev/null 2>&1
  cp weights.toml campaign.toml; printf "%b" "$extra" >> campaign.toml
  rm -rf "$out"
  # '@' separates words inside the --shell command template.
  set -- $args; argv=()
  while [ $# -gt 0 ]; do if [ "$1" = "--shell" ]; then argv+=("--shell" "${2//@/ }"); shift 2; else argv+=("$1"); shift; fi; done
  ./zig-out/bin/irx "${argv[@]}" --config campaign.toml --jobs 8 --seed 2026 --out "$out" --duration "$DUR" > "$out.log" 2>&1
  echo "$name rc=$?"
  git checkout -q campaign.toml 2>/dev/null || rm -f campaign.toml
done
git checkout -q main
echo ALL_DONE
