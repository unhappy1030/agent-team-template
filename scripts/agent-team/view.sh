#!/usr/bin/env bash
# 이 팀의 dashboard 세션에 바로 attach한다 (tmux attach -t 직접 타이핑하기 귀찮은 사람용).
# usage: agent-team view

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/_resolve.sh"

if ! tmux has-session -t "=$TEAM/dashboard" 2>/dev/null; then
  echo "대시보드 세션이 없습니다 (팀: $TEAM). 먼저 만드세요: scripts/agent-team/dashboard.sh" >&2
  exit 1
fi

exec tmux attach -t "=$TEAM/dashboard"
