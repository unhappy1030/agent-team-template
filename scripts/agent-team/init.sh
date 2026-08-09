#!/usr/bin/env bash
# 현재 프로젝트(기본: cwd, 인자로 경로 지정 가능)에 에이전트 팀을 처음부터 만든다.
# agent-team-template에서 .agent-mail과 scripts/agent-team을 복사해온다.
# usage: agent-team init [target-dir]
set -euo pipefail

TARGET="$(cd "${1:-.}" && pwd)"

if [[ -d "$TARGET/.agent-mail" ]]; then
  echo ".agent-mail이 이미 있습니다: $TARGET/.agent-mail (agent-team start로 진행하세요)" >&2
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

cp -r "$TEMPLATE_DIR/agent-mail-template" "$TARGET/.agent-mail"
mkdir -p "$TARGET/scripts"
[[ -d "$TARGET/scripts/agent-team" ]] || cp -r "$TEMPLATE_DIR/scripts/agent-team" "$TARGET/scripts/agent-team"

cat <<EOF
생성됨: $TARGET/.agent-mail
생성됨: $TARGET/scripts/agent-team (이미 있었으면 건너뜀)

다음 단계:
  cd "$TARGET"
  agent-team start   # role 파일의 <TODO>를 대화형으로 채운 뒤 팀을 띄웁니다
EOF
