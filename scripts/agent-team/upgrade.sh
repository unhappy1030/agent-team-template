#!/usr/bin/env bash
# scripts/agent-team를 템플릿 최신 버전으로 덮어쓴다. .agent-mail(roles/agents.conf 등
# 프로젝트별 커스터마이징)은 건드리지 않는다 - scripts/agent-team 코드만 대상.
# usage: agent-team upgrade
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$REPO_ROOT/scripts/agent-team"

# init.sh와 동일한 템플릿 소스 탐색: 로컬 클론 우선, 없으면 GitHub에서 임시로 클론.
find_template() {
  local candidate
  for candidate in "$HOME/repo/agent-team-template" "$HOME/repo/agent_team_template"; do
    [[ -d "$candidate/agent-mail-template" ]] && { echo "$candidate"; return; }
  done

  local tmp; tmp="$(mktemp -d)"
  git clone --depth 1 --quiet \
    https://github.com/unhappy1030/agent-team-template.git "$tmp" >&2
  echo "$tmp"
}

TEMPLATE_DIR="$(find_template)"

if [[ -d "$TEMPLATE_DIR/.git" ]]; then
  echo "템플릿 저장소 pull: $TEMPLATE_DIR"
  git -C "$TEMPLATE_DIR" pull --ff-only
fi

if [[ "$(cd "$TEMPLATE_DIR/scripts/agent-team" && pwd)" == "$DIR" ]]; then
  echo "여기가 이미 템플릿 저장소 자체입니다 - upgrade할 대상이 없습니다: $DIR" >&2
  exit 1
fi

echo "동기화: $TEMPLATE_DIR/scripts/agent-team -> $DIR"
mkdir -p "$DIR"
rsync -a --delete --exclude='__pycache__' "$TEMPLATE_DIR/scripts/agent-team/" "$DIR/"
chmod +x "$DIR"/*.sh "$DIR/agent-team"

cat <<EOF

완료. scripts/agent-team이 최신 버전으로 갱신됐습니다.
watch.py가 떠 있는 팀이 있다면 코드 변경을 반영하려면 재시작하세요: agent-team stop && agent-team start
EOF
