#!/usr/bin/env bash
# 현재 프로젝트(기본: cwd, 인자로 경로 지정 가능)에 에이전트 팀을 처음부터 만든다.
# agent-team-template에서 .agent-mail(-$TEAM)과 scripts/agent-team을 복사해온다.
# usage: agent-team init [target-dir]   (TEAM=<이름>이면 같은 저장소에 팀을 추가로 만든다)
set -euo pipefail

TARGET="$(cd "${1:-.}" && pwd)"

REPO_ROOT="$TARGET"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_resolve.sh"

if [[ -d "$MAILDIR" ]]; then
  echo "메일함이 이미 있습니다: $MAILDIR (agent-team start로 진행하거나, 다시 만들려면 agent-team reinit)" >&2
  exit 1
fi

# 템플릿 소스 찾기: 로컬 클론 우선, 없으면 GitHub에서 임시로 클론.
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

cp -r "$TEMPLATE_DIR/agent-mail-template" "$MAILDIR"
mkdir -p "$TARGET/scripts"
if [[ ! -d "$TARGET/scripts/agent-team" ]]; then
  cp -r "$TEMPLATE_DIR/scripts/agent-team" "$TARGET/scripts/agent-team"
  # 이 사본은 앞으로 이 경로($TARGET)에서만 쓰인다 - 매번 BASH_SOURCE로 재계산하는 대신
  # 지금 여기서 절대경로를 박아둔다. 잘못된 사본을 실행했을 때 REPO_ROOT 환경변수가
  # 새어들어와 조용히 다른 팀 메일함으로 가는 사고(agent-team-maildir-leak.md)도 함께 막는다.
  for f in "$TARGET/scripts/agent-team"/*.sh; do
    sed -i "s#^REPO_ROOT=.*REPO_ROOT:-.*#REPO_ROOT=\"$TARGET\"#" "$f"
  done
fi

start_cmd="agent-team start"
[[ "$TEAM" != "$(basename "$TARGET")" ]] && start_cmd="agent-team --team $TEAM start"

cat <<EOF
생성됨: $MAILDIR
생성됨: $TARGET/scripts/agent-team (이미 있었으면 건너뜀)

다음 단계:
  cd "$TARGET"
  $start_cmd   # role 파일의 <TODO>를 대화형으로 채운 뒤 팀을 띄웁니다
EOF
