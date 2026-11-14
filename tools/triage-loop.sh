#!/bin/bash
# Triage worker: takes runs from findings/forever/queue in order and gives each to a one-shot
# agy run, trying IRX_TRIAGE_MODELS in order (each falls through to the next when out of quota). Runs with no findings are marked clean without calling agy.
# Reports: findings/forever/triage/<run>.md; agy transcripts: findings/forever/triage/<run>.log
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
S=findings/forever; mkdir -p "$S/triage"; touch "$S/queue" "$S/triaged"
# Ledger edits happen in a separate worktree on origin/main (the fuzzer's checkout is never touched);
# when triage adds ledger rows, the loop commits them on triage/<run> and opens a PR.
WT=${IRX_LEDGER_WT:-$HOME/src/irx-ledger}
MODELS=(${IRX_TRIAGE_MODELS:-gemini-4-argon-medium gemini-4-hydrogen-medium claude-opus-5-5-low})
while :; do
  run=$(grep -vxFf <(cut -d" " -f1 "$S/triaged") "$S/queue" | head -1)
  if [ -z "$run" ]; then sleep 60; continue; fi
  name=$(basename "$run")
  # fuzz-forever deletes run data 2 runs later; a run that is already gone cannot be triaged.
  if [ ! -d "$run" ]; then echo "$run gone $(date -Is)" | tee -a "$S/triaged"; continue; fi
  n=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(\"findings\",0))" "$run/summary.json" 2>/dev/null || echo "?")
  if [ "$n" = 0 ]; then
    echo "$(date -Is) $name: no findings" | tee "$S/triage/$name.md"
    echo "$run clean $(date -Is)" >> "$S/triaged"; continue
  fi
  git -C "$WT" fetch -q origin main && git -C "$WT" checkout -q --detach origin/main && git -C "$WT" reset -q --hard && git -C "$WT" clean -qfd
  taken=$(for pr in $(gh pr list --state open --search "head:triage/" --json number -q ".[].number" 2>/dev/null); do gh pr diff "$pr" 2>/dev/null; done | grep -o "^+| IRX-[A-Z0-9]*-[0-9]*" | cut -c4- | sort -u | tr "\n" " ")
  ok=0
  for MODEL in "${MODELS[@]}"; do
  echo "== triage $name ($n findings) model=$MODEL $(date -Is)"
  timeout 3000 agy -p "$(cat tools/triage-prompt.md)

Run directory: $run
Write your report to: $S/triage/$name.md
Ledger checkout: $WT (edit $WT/README.md only)
Ledger IDs already taken by open PRs: ${taken:-none}" \
    --model "$MODEL" --dangerously-skip-permissions --print-timeout 48m > "$S/triage/$name.log" 2>&1
  rc=$?
  if grep -q "RESOURCE_EXHAUSTED" "$S/triage/$name.log"; then echo "$(date -Is) $name: $MODEL out of quota"; continue; fi
  ok=1; break
  done
  # Every model out of quota: leave the run queued and retry later instead of marking it triaged.
  if [ "$ok" = 0 ]; then echo "$(date -Is) all models out of quota; retrying in 30 min"; sleep 1800; continue; fi
  echo "$run rc=$rc $(date -Is)" | tee -a "$S/triaged"
  if ! git -C "$WT" diff --quiet; then
    br=triage/$name
    git -C "$WT" checkout -q -B "$br" && git -C "$WT" commit -qam "Ledger: new candidates from $name (unattended triage, $MODEL)" \
      && git -C "$WT" push -qf origin "$br" \
      && gh pr create -R robertmorelli/irx --base main --head "$br" --title "Ledger: new candidates from $name" \
           --body "Unattended triage ($MODEL) of \`findings/$name\` on porple added ledger rows. Review the repros before merging.

$(head -c 60000 "$S/triage/$name.md")" \
      && echo "$(date -Is) $name: opened ledger PR on $br" || echo "$(date -Is) $name: ledger commit/push/PR FAILED"
  fi
  [ -f "$S/triage/$name.md" ] && head -15 "$S/triage/$name.md"
done
