#!/usr/bin/env bash
# init의 반대: 이 팀의 메일함(.agent-mail 또는 .agent-mail-<team>)을 통째로 지운다.
# 실행 중인 세션/watch.py가 있으면 먼저 정리한다. 되돌릴 수 없으므로(메일 기록, role
# 파일에 채워둔 프로젝트 컨텍스트, agents.conf 커스터마이징이 모두 사라짐) 팀 이름을
# 그대로 입력하는 확인 절차를 거친다. -y/--yes로 건너뛸 수 있다.
# usage: agent-team uninstall [-y|--yes]
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$REPO_ROOT/scripts/agent-team"
source "$DIR/_resolve.sh"

if [[ ! -d "$MAILDIR" ]]; then
  echo "메일함이 없습니다: $MAILDIR (지울 게 없습니다)" >&2
  exit 1
fi

yes=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && yes=1

if [[ "$yes" -ne 1 ]]; then
  echo "삭제 대상: $MAILDIR (팀: $TEAM)"
  echo "메일 기록, role 파일의 프로젝트 컨텍스트, agents.conf 커스터마이징이 모두 사라지고 되돌릴 수 없습니다."
  if [[ ! -t 0 ]]; then
    echo "비대화형 실행이라 확인할 수 없습니다. -y/--yes를 주고 다시 실행하세요." >&2
    exit 1
  fi
  read -r -p "계속하려면 팀 이름(\"$TEAM\")을 그대로 입력하세요: " confirm
  if [[ "$confirm" != "$TEAM" ]]; then
    echo "취소됨." >&2
    exit 1
  fi
fi

"$DIR/stop.sh"

rm -rf "$MAILDIR"
echo "삭제됨: $MAILDIR (팀: $TEAM)"
