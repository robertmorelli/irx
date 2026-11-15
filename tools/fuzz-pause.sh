#!/bin/bash
# Pause or resume the fuzz-forever process tree (SIGSTOP/SIGCONT); triage is left alone.
# Usage: tools/fuzz-pause.sh stop|cont|status
set -u
root=$(pgrep -f '^/bin/bash tools/fuzz-forever.sh$' | head -1)
[ -n "$root" ] || { echo "fuzz-forever not running"; exit 1; }
all=($root); frontier=($root)
while [ ${#frontier[@]} -gt 0 ]; do
  next=()
  for p in "${frontier[@]}"; do next+=($(ps -o pid= --ppid "$p")); done
  frontier=("${next[@]}"); all+=("${next[@]}")
done
case "${1:-status}" in
  stop) kill -STOP "${all[@]}"; echo "paused ${#all[@]} processes";;
  cont) kill -CONT "${all[@]}"; echo "resumed ${#all[@]} processes";;
  *) ps -o pid=,stat=,args= -p "$(IFS=,; echo "${all[*]}")" | cut -c1-90;;
esac
