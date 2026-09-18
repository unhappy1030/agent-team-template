#!/usr/bin/env bash
# 현재 프로젝트(기본: cwd, 인자로 경로 지정 가능)에 에이전트 팀을 처음부터 만든다.
# agent-team-template에서 .agent-mail(-$TEAM)과 scripts/agent-team을 복사해온다.
# usage: agent-team init [target-dir] [--template <이름>]
#   TEAM=<이름>이면 같은 저장소에 팀을 추가로 만든다.
#   --template은 팀 구성(멤버/CLI/모델)을 고른다. 안 주면 템플릿이 여러 개일 때 물어본다.
set -euo pipefail

TEMPLATE="${TEMPLATE:-}"
_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --template|-t) TEMPLATE="${2:-}"; shift 2 ;;
    *) _args+=("$1"); shift ;;
  esac
done
TARGET="$(cd "${_args[0]:-.}" && pwd)"

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

# 팀 구성 템플릿 고르기: agent-mail-template(기본) + agent-mail-template-<이름> 들.
# 이름은 디렉터리 접미사 그대로 쓴다 ("agent-mail-template-gpt" -> "gpt", 기본은 "default").
tpl_name_of() {
  local base; base="$(basename "$1")"
  [[ "$base" == "agent-mail-template" ]] && echo "default" || echo "${base#agent-mail-template-}"
}

tpls=()
for d in "$TEMPLATE_DIR"/agent-mail-template*; do
  [[ -f "$d/agents.conf" ]] && tpls+=("$d")
done
[[ ${#tpls[@]} -gt 0 ]] || { echo "템플릿을 찾지 못했습니다: $TEMPLATE_DIR/agent-mail-template*" >&2; exit 1; }

TPL=""
if [[ -n "$TEMPLATE" ]]; then
  for d in "${tpls[@]}"; do
    [[ "$(tpl_name_of "$d")" == "$TEMPLATE" ]] && TPL="$d"
  done
  if [[ -z "$TPL" ]]; then
    echo "그런 템플릿이 없습니다: $TEMPLATE" >&2
    for d in "${tpls[@]}"; do echo "  - $(tpl_name_of "$d")" >&2; done
    exit 1
  fi
elif [[ ${#tpls[@]} -eq 1 || ! -t 0 ]]; then
  TPL="${tpls[0]}"
else
  echo "팀 구성 템플릿을 고르세요:"
  for d in "${tpls[@]}"; do
    # 주석/빈 줄 뺀 agents.conf 본문이 곧 팀 구성이라, 그대로 보여주면 설명이 필요 없다.
    echo "  [$(tpl_name_of "$d")]"
    grep -v -e '^#' -e '^[[:space:]]*$' "$d/agents.conf" | sed 's/^/      /'
  done
  echo
  PS3="번호 선택: "
  _names=(); for d in "${tpls[@]}"; do _names+=("$(tpl_name_of "$d")"); done
  select choice in "${_names[@]}"; do
    [[ -n "${choice:-}" ]] || continue
    for d in "${tpls[@]}"; do [[ "$(tpl_name_of "$d")" == "$choice" ]] && TPL="$d"; done
    break
  done
  [[ -n "$TPL" ]] || { echo "선택 안 됨" >&2; exit 1; }
fi

cp -r "$TPL" "$MAILDIR"
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
생성됨: $MAILDIR (템플릿: $(tpl_name_of "$TPL") — $(grep -c -v -e '^#' -e '^[[:space:]]*$' "$TPL/agents.conf")명)
생성됨: $TARGET/scripts/agent-team (이미 있었으면 건너뜀)

다음 단계:
  cd "$TARGET"
  $start_cmd   # role 파일의 <TODO>를 대화형으로 채운 뒤 팀을 띄웁니다
EOF
