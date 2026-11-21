#!/usr/bin/env bash
# Triage worker: takes runs from findings/forever/queue in order and gives each to a one-shot
# LLM CLI run, trying IRX_TRIAGE_MODELS in order (each falls through to the next when out of quota).
# Runs with no findings are marked clean without calling the CLI.
# Backend (IRX_TRIAGE_CLI): agy (Antigravity) or claude (Claude Code, print mode); default: agy if on PATH.
# Reports: findings/forever/triage/<run>.md; CLI transcripts: findings/forever/triage/<run>.log
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
S=findings/forever; mkdir -p "$S/triage"; touch "$S/queue" "$S/triaged"
now() { date +%Y-%m-%dT%H:%M:%S%z; }
HOST=$(hostname -s)
CLI=${IRX_TRIAGE_CLI:-$(command -v agy >/dev/null && echo agy || echo claude)}
if [ "$CLI" = agy ]; then DEF_MODELS="gemini-4-argon-medium gemini-4-hydrogen-medium claude-opus-5-5-low"
else DEF_MODELS="claude-opus-5-5"; fi
MODELS=(${IRX_TRIAGE_MODELS:-$DEF_MODELS})
# Ledger edits happen in a separate worktree on the ledger base (the fuzzer's checkout is never touched);
# when triage adds ledger rows, the loop commits them on triage/<run> and, if gh is installed, opens a PR.
WT=${IRX_LEDGER_WT:-$HOME/src/irx-ledger}
BASE=${IRX_LEDGER_BASE:-origin/main}
HAVE_GH=$(command -v gh >/dev/null && echo 1 || echo 0)
out_of_quota() { grep -qiE "RESOURCE_EXHAUSTED|usage limit|hit your (usage )?limit|rate.limit|limit reached|credit balance" "$1"; }
while :; do
  run=$(grep -vxFf <(cut -d" " -f1 "$S/triaged") "$S/queue" | head -1)
  if [ -z "$run" ]; then sleep 60; continue; fi
  name=$(basename "$run")
  # fuzz-forever deletes run data 2 runs later; a run that is already gone cannot be triaged.
  if [ ! -d "$run" ]; then echo "$run gone $(now)" | tee -a "$S/triaged"; continue; fi
  n=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(\"findings\",0))" "$run/summary.json" 2>/dev/null || echo "?")
  if [ "$n" = 0 ]; then
    echo "$(now) $name: no findings" | tee "$S/triage/$name.md"
    echo "$run clean $(now)" >> "$S/triaged"; continue
  fi
  git -C "$WT" fetch -q origin main 2>/dev/null   # best effort: hosts without GitHub access use the last fetched base
  git -C "$WT" checkout -q --detach "$BASE" && git -C "$WT" reset -q --hard && git -C "$WT" clean -qfd
  taken=""
  [ "$HAVE_GH" = 1 ] && taken=$(for pr in $(gh pr list --state open --search "head:triage/" --json number -q ".[].number" 2>/dev/null); do gh pr diff "$pr" 2>/dev/null; done | grep -o "^+| IRX-[A-Z0-9]*-[0-9]*" | cut -c4- | sort -u | tr "\n" " ")
  # Without gh, ledger branches committed earlier on this host stand in for open PRs.
  [ "$HAVE_GH" = 0 ] && taken=$(git -C "$WT" for-each-ref --format="%(refname)" refs/heads/triage | while read -r r; do git -C "$WT" diff "$BASE" "$r" -- README.md; done | grep -o "^+| IRX-[A-Z0-9]*-[0-9]*" | cut -c4- | sort -u | tr "\n" " ")
  prompt="$(cat tools/triage-prompt.md)

Run directory: $run
Write your report to: $S/triage/$name.md
Ledger checkout: $WT (edit $WT/README.md only)
Ledger IDs already taken by open PRs: ${taken:-none}
Host: $HOST
Label: ${name%-*}"
  ok=0
  for MODEL in "${MODELS[@]}"; do
    echo "== triage $name ($n findings) cli=$CLI model=$MODEL $(now)"
    if [ "$CLI" = agy ]; then
      timeout 3000 agy -p "$prompt" --model "$MODEL" --dangerously-skip-permissions --print-timeout 48m > "$S/triage/$name.log" 2>&1
    else
      timeout 3000 claude -p "$prompt" --model "$MODEL" --dangerously-skip-permissions < /dev/null > "$S/triage/$name.log" 2>&1
    fi
    rc=$?
    if [ "$rc" != 0 ] && out_of_quota "$S/triage/$name.log"; then echo "$(now) $name: $MODEL out of quota"; continue; fi
    ok=1; break
  done
  # Every model out of quota: leave the run queued and retry later instead of marking it triaged.
  if [ "$ok" = 0 ]; then echo "$(now) all models out of quota; retrying in 30 min"; sleep 1800; continue; fi
  echo "$run rc=$rc $(now)" | tee -a "$S/triaged"
  if ! git -C "$WT" diff --quiet; then
    br=triage/$name
    if git -C "$WT" checkout -q -B "$br" && git -C "$WT" commit -qam "Ledger: new candidates from $name (unattended triage, $MODEL)"; then
      if [ "$HAVE_GH" = 1 ] && git -C "$WT" push -qf origin "$br" \
        && gh pr create -R robertmorelli/irx --base main --head "$br" --title "Ledger: new candidates from $name" \
             --body "Unattended triage ($MODEL) of \`findings/$name\` on $HOST added ledger rows. Review the repros before merging.

$(head -c 60000 "$S/triage/$name.md")"; then
        echo "$(now) $name: opened ledger PR on $br"
      else
        echo "$(now) $name: ledger rows committed locally on $br in $WT (no PR opened)" | tee -a "$S/ledger-branches"
      fi
    else echo "$(now) $name: ledger commit FAILED"; fi
  fi
  [ -f "$S/triage/$name.md" ] && head -15 "$S/triage/$name.md"
done
