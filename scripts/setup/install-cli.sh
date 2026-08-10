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

# dashboard.sh 창(overview/agent별/mail) 전환용 tmux 단축키. Alt+1~9는 대부분 개인 tmux.conf에
# 이미 있는 흔한 설정이라 M-0만 빠져있는 경우가 많고, Alt+방향키는 보통 패널 이동에 이미 쓰이고
# 있어서 창 전환은 겹치지 않는 Ctrl+Alt로 뺀다.
TMUX_CONF="$HOME/.tmux.conf"
MARKER="# agent-team: dashboard 창 전환 단축키"
if ! grep -qF "$MARKER" "$TMUX_CONF" 2>/dev/null; then
  cat <<EOF >> "$TMUX_CONF"

$MARKER
bind -n M-0 select-window -t 0
bind -n C-M-Left previous-window
bind -n C-M-Right next-window
EOF
  echo "tmux 단축키 추가됨: $TMUX_CONF (Alt+0 창 0으로, Ctrl+Alt+←→ 이전/다음 창)"
  tmux source-file "$TMUX_CONF" 2>/dev/null || true
fi
