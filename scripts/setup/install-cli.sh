#!/usr/bin/env bash
# scripts/agent-team/agent-team를 ~/.local/bin/agent-team에 심볼릭 링크한다.
# 여러 저장소에 이 템플릿을 설치해도 마지막에 설치한 저장소의 스크립트로 링크가 잡히는데,
# 디스패처(agent-team) 자체는 매번 실행 시점의 cwd로 대상 저장소/팀을 찾으므로 상관없다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../agent-team" && pwd)"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$BIN_DIR"
ln -sf "$SCRIPT_DIR/agent-team" "$BIN_DIR/agent-team"
ln -sf "$SCRIPT_DIR/agent-team" "$BIN_DIR/agt"
echo "설치됨: $BIN_DIR/agent-team, $BIN_DIR/agt -> $SCRIPT_DIR/agent-team"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "PATH에 $BIN_DIR 이 없습니다. 셸 설정(.bashrc/.zshrc)에 아래 한 줄을 추가하세요:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
