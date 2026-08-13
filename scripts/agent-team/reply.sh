#!/usr/bin/env bash
# 원 메일의 발신자에게 답장을 보낸다.
# usage: reply.sh <from> <MSG-id> "<본문>"

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: reply.sh <from> <MSG-id> <body>" >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$DIR/../.." && pwd)}"
source "$DIR/_resolve.sh"

if [[ ! -f "$MAILDIR/agents.conf" ]]; then
  echo "⚠ $MAILDIR 에 agents.conf가 없습니다 (팀: $TEAM) - 아직 init/start 안 된 팀으로 보여 중단합니다." >&2
  echo "  reply.py가 이 경로를 그냥 새로 만들어버리면 아무도 안 보는 유령 메일함이 생깁니다." >&2
  exit 1
fi

echo "팀: $TEAM ($MAILDIR)" >&2
python3 "$DIR/reply.py" "$1" "$2" "$3"
