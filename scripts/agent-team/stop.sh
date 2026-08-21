#!/usr/bin/env bash
# watch.py와 이 팀의 tmux 세션(agents.conf에 정의된 에이전트 전체 + dashboard)을 모두 종료한다.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
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

if [[ -f "$MAILDIR/agents.conf" ]]; then
  while IFS=: read -r name cli model || [[ -n "$name" ]]; do
    name="$(echo "$name" | xargs)"
    [[ -z "$name" || "$name" == \#* ]] && continue
    if tmux kill-session -t "=$TEAM/$name" 2>/dev/null; then
      echo "tmux 세션 종료: $TEAM/$name"
    fi
  done < "$MAILDIR/agents.conf"
fi

if tmux kill-session -t "=$TEAM/dashboard" 2>/dev/null; then
  echo "tmux 세션 종료: $TEAM/dashboard"
fi

# context.md는 일부러 안 지운다 - 다음 start.sh에서 이어받을지 사람에게 묻는 근거가 된다.
[[ -s "$MAILDIR/context.md" ]] && echo "작업 컨텍스트 남김: $MAILDIR/context.md (다음 start에서 이어받을지 물어봅니다)"

echo "완료. (팀: $TEAM)"
