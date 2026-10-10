#!/bin/bash
# Run 10-minute campaigns for the JS-semantics engines, one branch each.
# Resumable: engines whose findings/<name>/summary.json exists are skipped.
set -u
R=$(cd "$(dirname "$0")/.." && pwd); cd "$R"
J=$R/vendor/jsvu-home/.jsvu/bin
PY=/opt/homebrew/bin/python3
HERMES_FLAGS='\n[flags]\nsets = ["", "i", "m", "s", "u", "iu", "im", "is", "ms", "ims", "imu", "isu", "msu", "imsu", "su", "mu"]\n'
run() { # name shellcmd selfcheck extra_toml
  local name=$1 cmd=$2 sc=$3 extra=$4
  if [ -f "findings/$name/summary.json" ]; then echo "$name: already done, skipping"; return; fi
  git checkout -q main && git checkout -q -B "$name" main
  cp weights.toml campaign.toml; printf "%b" "$extra" >> campaign.toml
  git add campaign.toml && git commit -q -m "$name: campaign config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KiiJG3o6tboGYXptjMZw65"
  rm -rf "findings/$name"
  ./zig-out/bin/irx --shell "$cmd" --config campaign.toml --jobs 8 --seed 777 --out "findings/$name" --duration 600 $sc > "findings/$name.log" 2>&1
  echo "$name done rc=$?"
}
run quickjs "/opt/homebrew/bin/qjs --std {driver} {mode}" "" ""
run xs "$PY $R/tools/bridge.py $J/xs {driver} {mode}" "" ""
run boa "$PY $R/tools/bridge.py $R/vendor/boa/bin/boa {driver} {mode}" "" ""
run engine262 "$PY $R/tools/bridge.py $R/vendor/node/node_modules/.bin/engine262 {driver} {mode}" "--no-selfcheck" ""
run hermes "$PY $R/tools/bridge.py $J/hermes {driver} {mode}" "--no-selfcheck" "$HERMES_FLAGS"
git checkout -q main
echo ALL_DONE
