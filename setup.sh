#!/usr/bin/env bash
# 새 머신 한 방 세팅 / 기존 머신 업데이트 (재실행 안전).
#   0) Node.js(없으면 nvm으로 설치)   1) claude CLI   2) antigravity CLI(agy)
#   3) agent-team/agt 명령 등록
#   4) codegraph + MCP 서버 + 스킬 + 플러그인 (install_skill_mcp_plugin.sh)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
export PATH="$HOME/.local/bin:$PATH"   # 이번 실행 중에 설치되는 codegraph/agt를 바로 잡으려고

echo "== 0/4 Node.js =="
# 없으면 nvm으로 깐다(배포판 무관, sudo 불필요). 이미 nvm이 있는데 PATH에만 없는 경우
# (비대화형 셸, default alias 비어있음 등)도 source + `nvm use --lts`로 살려 쓴다.
if ! command -v npm >/dev/null; then
  command -v curl >/dev/null || { echo "curl이 필요합니다" >&2; exit 1; }
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [[ -s "$NVM_DIR/nvm.sh" ]] || curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  command -v npm >/dev/null || nvm use --lts >/dev/null 2>&1 || nvm install --lts
  command -v npm >/dev/null || { echo "Node.js 설치 실패 - https://nodejs.org 에서 직접 설치하세요" >&2; exit 1; }
  echo "  node $(node -v) / npm $(npm -v) (새 셸에서도 쓰려면 터미널을 다시 열 것)"
else
  echo "  이미 설치됨: node $(node -v)"
fi

echo
echo "== 1/4 claude CLI =="
npm install -g @anthropic-ai/claude-code@latest

echo
echo "== 2/4 antigravity CLI (agy) =="
if command -v agy >/dev/null; then
  agy update || echo "  agy update 실패 - 무시하고 계속"
else
  echo "  agy 없음: https://antigravity.google 에서 설치한 뒤 'agy install'을 실행하세요."
  echo "  (agy가 없으면 아래 단계에서 agy용 MCP/스킬 등록은 건너뜁니다)"
fi

echo
echo "== 3/4 agent-team / agt 명령 등록 =="
scripts/setup/install-cli.sh

echo
echo "== 4/4 codegraph + MCP + 스킬 + 플러그인 =="
scripts/setup/install_skill_mcp_plugin.sh

echo
echo "완료. 새 프로젝트에서는 'agent-team init' 후 'agent-team start'."
