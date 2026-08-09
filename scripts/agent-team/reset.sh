#!/usr/bin/env bash
# 메일함 상태만 초기화한다: inbox.md/relay.log/watch.processed/NEEDS_ATTN을 비운다.
# role 파일과 agents.conf는 건드리지 않는다 (그건 reinit의 일 — 이 커맨드는 "메일 큐만
# 비우고 싶다"는 더 가벼운 경우용).
#
# watch.py가 떠 있으면 재시작한다: watch.py는 자기 프로세스 메모리에 "이미 처리한
# MSG-id" 집합을 들고 있는데, inbox.md를 비우면 다음 메일이 다시 MSG-0001부터
# 채번되므로 재시작 없이 두면 메모리 속 옛 MSG-0001 처리 기록과 충돌해 새 메일 알림이
# 조용히 씹힐 수 있다.
# usage: agent-team reset [-y|--yes]
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$REPO_ROOT/scripts/agent-team"
source "$DIR/_resolve.sh"

if [[ ! -d "$MAILDIR" ]]; then
  echo "메일함이 없습니다: $MAILDIR" >&2
  exit 1
fi

yes=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && yes=1

if [[ "$yes" -ne 1 ]]; then
  echo "초기화 대상: $MAILDIR (팀: $TEAM)"
  echo "inbox.md/relay.log/watch.processed/NEEDS_ATTN이 모두 비워지고 메일 기록이 사라집니다."
  echo "(role 파일, agents.conf는 그대로 유지됩니다.)"
  if [[ ! -t 0 ]]; then
    echo "비대화형 실행이라 확인할 수 없습니다. -y/--yes를 주고 다시 실행하세요." >&2
    exit 1
  fi
  read -r -p "계속하시겠습니까? (y/N) " confirm
  [[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "취소됨." >&2; exit 1; }
fi

watch_running=0
if [[ -f "$MAILDIR/watch.pid" ]] && kill -0 "$(cat "$MAILDIR/watch.pid")" 2>/dev/null; then
  watch_running=1
  "$DIR/stop.sh"
fi

: > "$MAILDIR/relay.log"
rm -f "$MAILDIR/NEEDS_ATTN"
: > "$MAILDIR/watch.processed"
: > "$MAILDIR/inbox.md"

if [[ "$watch_running" -eq 1 ]]; then
  nohup python3 "$DIR/watch.py" >> "$MAILDIR/relay.log" 2>&1 &
  echo $! > "$MAILDIR/watch.pid"
  echo "watch.py 재시작 (pid $(cat "$MAILDIR/watch.pid"))"
fi

echo "초기화됨: $MAILDIR (팀: $TEAM)"
