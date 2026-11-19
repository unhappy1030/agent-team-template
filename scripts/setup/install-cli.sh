#!/usr/bin/env bash
# scripts/agent-team/agent-team를 ~/.local/bin/agent-team에 심볼릭 링크한다.
# 여러 저장소에 이 템플릿을 설치해도 마지막에 설치한 저장소의 스크립트로 링크가 잡히는데,
# 디스패처(agent-team) 자체는 매번 실행 시점의 cwd로 대상 저장소/팀을 찾으므로 상관없다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../agent-team" && pwd)"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$BIN_DIR"

# Git Bash(MSYS)는 기본 설정에서 ln -s가 심볼릭 링크가 아니라 "파일 복사"로 떨어진다. 복사본은
# readlink -f로도 원본 위치를 되짚을 수 없어서 디스패처가 자기 옆의 init.sh/start.sh를 못 찾는다
# (agt init이 조용히 실패하는 원인). 링크가 안 만들어졌으면 원본 경로를 박은 래퍼를 쓴다.
link_cmd() {
  local dest="$1"
  rm -f "$dest"
  ln -s "$SCRIPT_DIR/agent-team" "$dest" 2>/dev/null || true
  [[ -L "$dest" ]] && return 0
  printf '#!/usr/bin/env bash\nexec "%s/agent-team" "$@"\n' "$SCRIPT_DIR" > "$dest"
  chmod +x "$dest"
  echo "  심볼릭 링크를 못 만들어 래퍼 스크립트로 설치했습니다: $dest"
}

link_cmd "$BIN_DIR/agent-team"
link_cmd "$BIN_DIR/agt"
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
# 블록마다 마커가 따로라, 나중에 추가된 블록도 기존 설치에 재실행만으로 붙는다.
add_tmux_block() {  # <마커> <안내 문구>, 본문은 stdin
  local body
  body="$(cat)"
  grep -qF "$1" "$TMUX_CONF" 2>/dev/null && return 0
  printf '\n%s\n%s\n' "$1" "$body" >> "$TMUX_CONF"
  echo "$2"
  tmux source-file "$TMUX_CONF" 2>/dev/null || true
}

add_tmux_block "# agent-team: dashboard 창 전환 단축키" \
  "tmux 단축키 추가됨: $TMUX_CONF (Alt+0 창 0으로, Ctrl+Alt+←→ 이전/다음 창)" <<'EOF'
bind -n M-0 select-window -t 0
bind -n C-M-Left previous-window
bind -n C-M-Right next-window
EOF

# dashboard.sh가 mouse on을 켜면 패널 우클릭에 tmux 기본 메뉴(분할/종료 등)가 떠서 실수로 창이
# 쪼개진다. 메뉴만 끈다(Shift+우클릭은 터미널 자체 메뉴/붙여넣기 그대로).
add_tmux_block "# agent-team: 패널 우클릭 메뉴 끄기" \
  "tmux 우클릭 메뉴 끔: $TMUX_CONF" <<'EOF'
unbind -n MouseDown3Pane
unbind -n M-MouseDown3Pane
EOF
