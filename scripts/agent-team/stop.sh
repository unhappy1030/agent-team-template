#!/usr/bin/env bash
# watch.py를 중지한다. --kill-sessions를 주면 agents.conf에 정의된 tmux 세션도 함께 종료한다.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/_resolve.sh"

if [[ -f "$MAILDIR/watch.pid" ]]; then
  pid="$(cat "$MAILDIR/watch.pid")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "watch.py 종료 (pid $pid)"
  fi
  rm -f "$MAILDIR/watch.pid"
else
  echo "watch.pid 없음 (실행 중이 아닌 것으로 보임)"
fi

if [[ "${1:-}" == "--kill-sessions" && -f "$MAILDIR/agents.conf" ]]; then
  while IFS=: read -r name cli model || [[ -n "$name" ]]; do
    name="$(echo "$name" | xargs)"
    [[ -z "$name" || "$name" == \#* ]] && continue
    if tmux kill-session -t "=$TEAM/$name" 2>/dev/null; then
      echo "tmux 세션 종료: $TEAM/$name"
    fi
  done < "$MAILDIR/agents.conf"
fi

echo "완료. (팀: $TEAM)"
