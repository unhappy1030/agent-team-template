#!/usr/bin/env bash
# 이 저장소를 세팅한 머신에 현재 설치돼 있는 MCP 서버 / 스킬 / 플러그인을 새 머신에서도
# 동일하게 설치한다 (claude + antigravity + codex). README의 "MCP 서버 설정"/"스킬 설정" 절차를
# 그대로 스크립트로 옮긴 것 - 무엇을 설치하는지는 이 파일이 최신 출처(~/.agents/.skill-lock.json,
# claude mcp list, claude plugin list 실측 결과)다.
#
# codegraph는 이 스크립트가 직접 설치/업그레이드한 뒤 MCP 서버로 등록한다.
# graphify(uv tool)처럼 별도 설치 스크립트를 쓰는 도구는 여전히 대상 밖이다.

set -euo pipefail

command -v npx >/dev/null || { echo "npx가 필요합니다 (Node.js 설치 필요)" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl이 필요합니다" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI가 필요합니다: npm install -g @anthropic-ai/claude-code" >&2; exit 1; }

echo "== 1/3 codegraph + MCP 서버 (codegraph, playwright) =="

export PATH="$HOME/.local/bin:$PATH"
if command -v codegraph >/dev/null; then
  codegraph upgrade || echo "  codegraph upgrade 실패 - 기존 버전으로 계속"
else
  curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
fi
CODEGRAPH_BIN="$(command -v codegraph || true)"

add_mcp_claude() {
  local name="$1"; shift
  if claude mcp list 2>/dev/null | grep -q "^$name:"; then
    echo "  claude: $name 이미 등록됨"
  else
    claude mcp add "$name" -- "$@" && echo "  claude: $name 등록"
  fi
}

# agy는 ~/.gemini/config/mcp_config.json을 읽는데, `agy mcp add`가 그 파일을 갱신해준다
# (있으면 덮어씀). agy가 없으면 이 등록만 건너뛴다.
add_mcp_agy() {
  command -v agy >/dev/null || return 0
  local name="$1"; shift
  agy mcp add "$name" -- "$@" >/dev/null && echo "  agy: $name 등록"
}

# codex는 ~/.codex/config.toml을 `codex mcp add`가 갱신한다. codex가 없으면 건너뛴다.
add_mcp_codex() {
  command -v codex >/dev/null || return 0
  local name="$1"; shift
  codex mcp add "$name" -- "$@" >/dev/null && echo "  codex: $name 등록"
}

if [[ -n "$CODEGRAPH_BIN" ]]; then
  add_mcp_claude codegraph "$CODEGRAPH_BIN" serve --mcp
  add_mcp_agy codegraph "$CODEGRAPH_BIN" serve --mcp
  add_mcp_codex codegraph "$CODEGRAPH_BIN" serve --mcp
fi
add_mcp_claude playwright npx -y @playwright/mcp@latest
add_mcp_agy playwright npx -y @playwright/mcp@latest
add_mcp_codex playwright npx -y @playwright/mcp@latest

echo
echo "== 2/3 스킬 (npx skills add) =="

# "repo owner/name" "스킬 이름들..." - ~/.agents/.skill-lock.json 실측 기준. 저장소당 한 번만
# 호출해서 정확히 지금 설치돼 있는 스킬만 받는다(레포에 그 뒤로 스킬이 늘어도 영향 없게 -s로 고정).
SKILL_GROUPS=(
  "forrestchang/andrej-karpathy-skills|karpathy-guidelines"
  "juliusbrussee/caveman|cavecrew caveman caveman-commit caveman-compress caveman-help caveman-review caveman-stats"
  "nextlevelbuilder/ui-ux-pro-max-skill|banner-design brand design design-system slides ui-styling ui-ux-pro-max"
  "mattpocock/skills|grill-me handoff"
  "anthropics/skills|skill-creator"
  "obra/superpowers|brainstorming dispatching-parallel-agents executing-plans finishing-a-development-branch receiving-code-review requesting-code-review subagent-driven-development systematic-debugging test-driven-development using-git-worktrees using-superpowers verification-before-completion writing-plans writing-skills"
  "awesome-skills/code-review-skill|code-review-skill"
  "lackeyjb/playwright-skill|playwright-skill"
  "mksglu/context-mode|context-mode ctx-doctor ctx-index ctx-insight ctx-purge ctx-search ctx-stats ctx-upgrade context-mode-ops"
)

for group in "${SKILL_GROUPS[@]}"; do
  repo="${group%%|*}"
  names="${group#*|}"
  echo "  $repo -> $names"
  # shellcheck disable=SC2086
  npx skills add "$repo" -g -a claude-code antigravity-cli -y -s $names
done

echo
echo "== 3/3 antigravity용 스킬 심볼릭 링크 동기화 =="
"$(dirname "${BASH_SOURCE[0]}")/sync-antigravity-skills.sh"

echo
echo "== 플러그인 (ponytail) =="
if claude plugin list 2>/dev/null | grep -q "ponytail@ponytail"; then
  echo "  ponytail 이미 설치됨"
else
  claude plugin marketplace add DietrichGebert/ponytail
  claude plugin install ponytail@ponytail
fi

echo
echo "완료. codegraph 바이너리, graphify(uv tool)처럼 이 스크립트가 설치하지 않는 도구는"
echo "각자 원래 설치 방법대로 먼저 설치해두면 MCP 등록 단계에서 자동으로 잡힌다."
