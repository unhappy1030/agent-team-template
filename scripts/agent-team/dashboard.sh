#!/usr/bin/env bash
# agents.conf에 정의된, 현재 실행 중인 에이전트 세션들을 볼 수 있는 대시보드 세션을 만든다.
#
# 창(탭) 구성:
#   overview - 전체 세션을 타일로 동시에 보여줌 (한눈에 훑어보기용)
#   <agent>  - 에이전트별 전용 창, 전체 화면 (탭처럼 전환)
#   mail     - .agent-mail/relay.log, inbox.md 실시간 tail (메일 내용 확인용)
#   usage    - 에이전트별 토큰 사용량과 codex 한도 (usage.py를 30초마다 실행)
#
# 각 pane/창은 해당 세션에 실제로 붙은 두 번째 클라이언트라 타이핑도 그대로 먹는다 —
# 단, prefix 키(Ctrl-b)는 대시보드 세션 자체가 먼저 가로챈다.
# 마우스가 켜져 있어 하단 상태줄의 창 이름 클릭으로 창 전환, pane 클릭으로 포커스 이동,
# 스크롤휠로 스크롤백을 볼 수 있다.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # usage 창 셸에 넘길 때 절대경로여야 한다
source "$DIR/_resolve.sh"
DASH="$TEAM/dashboard"

if [[ ! -f "$MAILDIR/agents.conf" ]]; then
  echo "agents.conf 없음: $MAILDIR/agents.conf" >&2
  exit 1
fi

names=()
while IFS=: read -r name cli model || [[ -n "$name" ]]; do
  name="$(echo "$name" | xargs)"
  [[ -z "$name" || "$name" == \#* ]] && continue
  names+=("$name")
done < "$MAILDIR/agents.conf"

running=()
for n in "${names[@]}"; do
  if tmux has-session -t "=$TEAM/$n" 2>/dev/null; then
    running+=("$n")
  else
    echo "건너뜀 (세션 없음): $TEAM/$n" >&2
  fi
done

if [[ ${#running[@]} -eq 0 ]]; then
  echo "실행 중인 에이전트 세션이 없습니다 (팀: $TEAM). 먼저 start.sh를 실행하세요." >&2
  exit 1
fi

tmux kill-session -t "=$DASH" 2>/dev/null || true

# overview 창: 전체 세션 타일
first="${running[0]}"
tmux new-session -d -s "$DASH" -n overview "unset TMUX; tmux attach -t '=$TEAM/$first'"
# #T(활성 pane의 title)를 보여주는 테마에서는 창 하나가 아니라 pane마다 따로 title이
# 필요하다 - split-window는 매번 새 pane을 활성으로 만들어 활성이 계속 옮겨가므로,
# 창 전체에 한 번만 title을 걸면 나중에 만들어진(제목 없는) pane으로 밀려나 사라진다.
# 그래서 pane마다 생성 직후(=활성인 순간) 그 pane이 보여주는 에이전트 이름으로 건다.
tmux select-pane -t "=$DASH:overview" -T "$first"

# window-size=latest(기본값) 때문에 detached로 만든 세션은 "서버에서 가장 최근 클라이언트"의
# 크기를 물려받는다 (-x/-y 플래그도 이때는 무시된다). 이 스크립트가 pane 안에서 tmux attach를
# 중첩으로 띄우는 구조라 작은 pane에 붙은 클라이언트가 그대로 남고, 다음 실행이 그 크기를
# 물려받는 피드백 루프가 생긴다. 1행짜리 좀비 클라이언트가 하나라도 있으면 80x1로 태어나
# 첫 split-window가 "no space for new pane"으로 실패한다.
# 레이아웃을 짜는 동안만 크기를 고정하고, 다 만든 뒤 latest로 되돌려 attach 시 터미널에 맞춘다.
tmux set-option -t "=$DASH:" window-size manual
tmux set-option -t "=$DASH:" default-size 200x50
tmux resize-window -t "=$DASH:overview" -x 200 -y 50

for n in "${running[@]:1}"; do
  tmux split-window -t "=$DASH:overview" "unset TMUX; tmux attach -t '=$TEAM/$n'"
  tmux select-pane -t "=$DASH:overview" -T "$n"
  tmux select-layout -t "=$DASH:overview" tiled >/dev/null
done
tmux select-layout -t "=$DASH:overview" tiled >/dev/null

# 에이전트별 전용 창 (탭으로 전환하며 전체 화면으로 보기)
for n in "${running[@]}"; do
  tmux new-window -t "=$DASH" -n "$n" "unset TMUX; tmux attach -t '=$TEAM/$n'"
  # 창을 여는 셸이 뜨자마자(개인 셸 rc의 흔한 관행) OSC로 pane title을 호스트/유저명으로
  # 한 번 세팅하고 그 뒤로 아무도 안 바꿔서 그 값이 그대로 굳는다. 창 이름(#W)을 쓰는
  # 기본 테마라면 안 보이는 문제지만, pane title(#T)을 보여주는 테마에서는 상태줄 탭이
  # 전부 그 문구로 뒤덮인다. 창 이름과 같은 값으로 title을 직접 박아 덮어쓴다.
  tmux select-pane -t "=$DASH:$n" -T "$n"
done

# mail 창: relay.log / inbox.md 실시간 tail
tmux new-window -t "=$DASH" -n mail
tmux select-pane -t "=$DASH:mail" -T relay
tmux send-keys -t "=$DASH:mail" "tail -n 100 -f '$MAILDIR/relay.log'" Enter
tmux split-window -t "=$DASH:mail" -h
tmux select-pane -t "=$DASH:mail" -T inbox
tmux send-keys -t "=$DASH:mail" "tail -n 100 -f '$MAILDIR/inbox.md'" Enter
tmux select-layout -t "=$DASH:mail" even-horizontal >/dev/null

# usage 창: 에이전트별 토큰 사용량 + codex 한도. 30초마다 다시 그린다(로그 파일을 읽을 뿐이라 쌈).
# send-keys로 셸에 넣는 건 mail 창과 같은 이유다 - 루프가 죽어도 창이 닫히지 않고 셸이 남는다.
tmux new-window -t "=$DASH" -n usage
tmux send-keys -t "=$DASH:usage" \
  "while :; do clear; MAILDIR='$MAILDIR' TEAM='$TEAM' REPO_ROOT='$REPO_ROOT' python3 '$DIR/usage.py'; sleep 30; done" Enter

# -t "=$DASH" (콜론 없는 exact-match)는 세션 대상 set-option에서 "no such session"으로
# 실패하는 tmux 버그가 있다(has-session/kill-session은 멀쩡함). 콜론을 붙이면 정상 동작한다.
tmux set-option -t "=$DASH:" mouse on
tmux set-option -t "=$DASH:" window-size latest

# 레이아웃을 짜는 동안 걸어둔 수동 크기를 전부 풀어(-A = automatic), 모든 창이 attach한 터미널
# 크기를 따르게 한다. 안 풀면 overview는 위에서 resize-window로 박은 200x50에 영구히 고정되고,
# 그 뒤에 만든 창들은 window-size manual 상태에서 태어나느라 1행짜리로 남는다 - 그 1행 창 안에서
# tmux attach가 에이전트 세션에 아주 작은 클라이언트로 붙고, 에이전트 세션은 window-size largest라
# 창 크기와 실제로 그려진 크기가 어긋나 화면이 깨져 보였다 (에이전트가 많을수록 심해진다).
for w in overview "${running[@]}" mail usage; do
  tmux resize-window -A -t "=$DASH:$w" 2>/dev/null || true
done

# 위 -A는 클라이언트가 붙어 있을 때만 실제로 다시 계산된다. 이 스크립트는 항상 클라이언트 없이
# (detached) 대시보드를 만들므로, 나중에 agt view로 붙는 순간 한 번 더 풀어줘야 창들이 그 터미널
# 크기를 따른다. 안 그러면 attach해도 만들 때 크기(200x50)에 박제된 채로 남아 화면이 어긋난다.
tmux set-hook -t "=$DASH:" client-attached \
  "run-shell \"tmux list-windows -t '=$DASH' -F '##{window_id}' | xargs -n1 -I@ tmux resize-window -A -t @\""

# window-size=latest면 tmux가 현재 창을 클라이언트 크기에 맞추고, 다른 창은 그 창으로
# 전환하는 순간 맞춰준다(tiled 레이아웃도 비율대로 같이 스케일됨) - 별도 훅 불필요.
# (예전엔 여기서 resize-window -x "#{client_width}" 훅을 걸었으나, resize-window의
#  -x/-y는 format을 확장하지 않아 매번 "width invalid"로 실패했고, 훅 안에서 에러가
#  나면 ';' 체인이 거기서 끊겨 window-size가 manual에 박제된 채 다시는 latest로
#  안 돌아왔다 - 창들이 생성 당시 크기(mail 3x50 등)에 영구히 눌러붙어 있었고, 그 결과
#  화면에 "Width invalid" 에러와 tmux의 빈 공간 채움 문자(·)가 그대로 보이던 것이었다.
#  거기다 $DASH도 단따옴표 안이라 치환 안 되고 tmux 쪽에서 빈 값으로 풀려 =: 세션을
#  가리키고 있었다 - 즉 애초에 제대로 실행된 적이 없는 코드.)

tmux select-window -t "=$DASH:overview"

cat <<EOF
대시보드 생성됨 (팀: $TEAM, ${#running[@]}개 세션: ${running[*]})

  tmux attach -t "=$DASH"

창(탭) 목록: overview, ${running[*]}, mail, usage
  - overview: 전체 세션 타일 뷰
  - ${running[*]}: 에이전트별 전용 전체 화면 창
  - mail: relay.log(왼쪽) / inbox.md(오른쪽) 실시간 tail
  - usage: 에이전트별 토큰 사용량 + codex 한도 (30초 갱신)

마우스 사용 가능: 하단 상태줄의 창 이름을 클릭하면 그 창으로 전환, pane을 클릭하면
포커스 이동, 스크롤휠로 스크롤백 확인이 됩니다.
주의: Ctrl-b(prefix)는 대시보드 세션이 먼저 가로챕니다 — 개별 세션에서 prefix
명령을 쓰고 싶으면 대시보드에서 나가서 tmux attach -t <세션명> 으로 개별 접속하세요.
EOF
