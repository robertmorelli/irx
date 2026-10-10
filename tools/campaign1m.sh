#!/bin/bash
# 1-minute smoke campaign on every engine branch. Resumable: skips branches whose
# findings/1m-<name>/summary.json exists. Usage: tools/campaign1m.sh [names...]
set -u
R=$(cd "$(dirname "$0")/.." && pwd); cd "$R"
J=$R/vendor/jsvu-home/.jsvu/bin; PY=/opt/homebrew/bin/python3; H=$R/hosts/bin
NOLOOK='\n[weights]\nlookahead = 0\nneg_lookahead = 0\nlookbehind = 0\nneg_lookbehind = 0\n'
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
)
want=" ${*:-} "
for t in "${TARGETS[@]}"; do
  IFS='|' read -r name args extra <<<"$t"
  [ "$want" != "  " ] && [[ "$want" != *" $name "* ]] && continue
  out="findings/1m-$name"
  if [ -f "$out/summary.json" ]; then echo "$name: done, skipping"; continue; fi
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
