#!/usr/bin/env bash
# Start/stop the unattended runner (fuzz-forever + triage-loop) without tmux, via daemon(8) on FreeBSD
# or nohup elsewhere. Consoles: findings/forever/{fuzz,triage}.console; pids: findings/forever/*.pid.
#   IRX_TARGETS=perl-blead IRX_LABEL=ed tools/runner.sh start|stop|status
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
S=findings/forever; mkdir -p "$S"
BASH_BIN=$(command -v bash)
alive() { [ -f "$S/$1.pid" ] && kill -0 "$(cat "$S/$1.pid")" 2>/dev/null; }
start() { # name script
  if alive "$1"; then echo "$1 already running (pid $(cat "$S/$1.pid"))"; return; fi
  if command -v daemon >/dev/null && [ "$(uname)" = FreeBSD ]; then
    daemon -f -o "$S/$1.console" -p "$S/$1.pid" "$BASH_BIN" "$2"
  else
    nohup "$BASH_BIN" "$2" >> "$S/$1.console" 2>&1 < /dev/null & echo $! > "$S/$1.pid"
  fi
  sleep 1; alive "$1" && echo "$1 started (pid $(cat "$S/$1.pid"))" || echo "$1 FAILED to start; see $S/$1.console"
}
stop() { # kill the whole tree under the recorded pid
  alive "$1" || { echo "$1 not running"; return; }
  local all=($(cat "$S/$1.pid")) frontier=($(cat "$S/$1.pid")) next p
  while [ ${#frontier[@]} -gt 0 ]; do next=(); for p in "${frontier[@]}"; do next+=($(pgrep -P "$p")); done; frontier=("${next[@]}"); all+=("${next[@]}"); done
  kill -TERM "${all[@]}" 2>/dev/null; rm -f "$S/$1.pid"; echo "$1 stopped (${#all[@]} processes)"
}
case "${1:-status}" in
  start) start fuzz tools/fuzz-forever.sh; start triage tools/triage-loop.sh;;
  stop) stop fuzz; stop triage;;
  *) for n in fuzz triage; do alive $n && echo "$n: running (pid $(cat "$S/$n.pid"))" || echo "$n: stopped"; done
     echo "round $(cat "$S/round" 2>/dev/null || echo 1)"; tail -3 "$S/fuzz.console" 2>/dev/null; tail -3 "$S/triage.console" 2>/dev/null;;
esac
