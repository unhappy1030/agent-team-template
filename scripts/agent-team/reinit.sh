#!/usr/bin/env bash
# uninstall.sh + init.sh: 이 팀의 메일함을 지우고 템플릿에서 다시 만든다.
# role 파일 커스터마이징과 메일 기록이 초기화되고 agents.conf도 템플릿 기본값으로
# 돌아간다 — 온보딩을 처음부터 다시 하고 싶을 때, 또는 메일함 상태가 꼬였을 때 쓴다.
# usage: agent-team reinit [-y|--yes]
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$REPO_ROOT/scripts/agent-team"
source "$DIR/_resolve.sh"

if [[ -d "$MAILDIR" ]]; then
  "$DIR/uninstall.sh" "$@"
fi

TEAM="$TEAM" "$DIR/init.sh" "$REPO_ROOT"
