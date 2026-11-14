#!/bin/bash
# Fuzz forever: rounds of IRX_DUR-second campaigns (default 45 min) over TARGETS on all cores.
# Each finished run is appended to findings/forever/queue for tools/triage-loop.sh.
# Resumable: a restart skips targets already done in the current round (findings/forever/done).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
DUR=${IRX_DUR:-2700} JOBS=${IRX_JOBS:-$(nproc)} MIN_FREE=${IRX_MIN_FREE_GB:-10}
TARGETS=(${IRX_TARGETS:-re2 oniguruma icu-c boost-regex libc-regex llvm-regex})
S=findings/forever; mkdir -p "$S"; touch "$S/done" "$S/queue"
round=$(cat "$S/round" 2>/dev/null || echo 1)
while :; do
  for t in "${TARGETS[@]}"; do
    label=linux45-r$round
    grep -q "^$label $t " "$S/done" && continue
    while free=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ "$free" -lt "$MIN_FREE" ]; do
      echo "$(date -Is) only ${free}G free (< ${MIN_FREE}G); waiting"; sleep 600; done
    seed=$(date +%s)
    echo "== round $round  $t  seed=$seed  jobs=$JOBS  $(date -Is)"
    tools/irx_target.py "$t" --label "$label" --duration "$DUR" --jobs "$JOBS" --seed "$seed" --no-readme | tail -2
    rc=${PIPESTATUS[0]}
    echo "$label $t rc=$rc seed=$seed $(date -Is)" | tee -a "$S/done"
    echo "findings/$label-$t" >> "$S/queue"
    # Run data is only kept for triage: delete the run that finished 2 runs before this one.
    if [ "$(wc -l < "$S/done")" -ge 3 ]; then
      read -r ol ot _ < <(tail -3 "$S/done" | head -1)
      [ -d "findings/$ol-$ot" ] && { echo "$(date -Is) deleting findings/$ol-$ot"; rm -rf "findings/$ol-$ot" "findings/$ol-$ot.log"; }
    fi
  done
  round=$((round + 1)); echo "$round" > "$S/round"
done
