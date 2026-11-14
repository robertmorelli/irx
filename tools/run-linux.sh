#!/bin/bash
# Resumable campaign runner (Linux box). Runs tools/irx_target.py over a target list, one at a time,
# and appends "NAME: rc=N" to findings/<label>.runlog. Rerunning with the same label skips every
# target that already has an rc line, so after a reboot it resumes at the first unfinished target.
# The seed is chosen once (date +%s) and kept in the runlog so a resumed run uses the same one.
#
#   tools/run-linux.sh LABEL DURATION_SECONDS JOBS TARGET...
#   e.g. tmux new -s irx 'tools/run-linux.sh linux-30m 1800 8 pcre2 re2 oniguruma'
set -u
[ $# -ge 4 ] || { sed -n 2,9p "$0"; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
LABEL=$1 DUR=$2 JOBS=$3; shift 3
mkdir -p findings; LOG=findings/$LABEL.runlog
SEED=$(sed -n 's/^# seed=\([0-9]*\).*/\1/p' "$LOG" 2>/dev/null | head -1)
[ -n "$SEED" ] || { SEED=$(date +%s); echo "# seed=$SEED label=$LABEL duration=$DUR jobs=$JOBS started=$(date -Is)" >> "$LOG"; }
echo "label=$LABEL seed=$SEED duration=${DUR}s jobs=$JOBS targets=$*"
for t in "$@"; do
  if grep -q "^$t: rc=" "$LOG"; then echo "skip $t ($(grep "^$t: rc=" "$LOG"))"; continue; fi
  echo "disk: $(df -h --output=used,avail / | tail -1)"
  FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ "$FREE_GB" -ge "${IRX_MIN_FREE_GB:-10}" ] || { echo "stopping: only ${FREE_GB}G free (< ${IRX_MIN_FREE_GB:-10}G)"; exit 3; }
  echo "== $t $(date -Is)"
  tools/irx_target.py "$t" --label "$LABEL" --duration "$DUR" --jobs "$JOBS" --seed "$SEED" | tail -1
  echo "$t: rc=${PIPESTATUS[0]}" | tee -a "$LOG"
done
echo "done $(date -Is)"
