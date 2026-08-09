#!/usr/bin/env bash
# agents.conf에 정의된, 현재 실행 중인 에이전트 세션들을 볼 수 있는 대시보드 세션을 만든다.
#
# 창(탭) 구성:
#   overview - 전체 세션을 타일로 동시에 보여줌 (한눈에 훑어보기용)
#   <agent>  - 에이전트별 전용 창, 전체 화면 (탭처럼 전환)
#   mail     - .agent-mail/relay.log, inbox.md 실시간 tail (메일 내용 확인용)
#
# 각 pane/창은 해당 세션에 실제로 붙은 두 번째 클라이언트라 타이핑도 그대로 먹는다 —
# 단, prefix 키(Ctrl-b)는 대시보드 세션 자체가 먼저 가로챈다.
# 마우스가 켜져 있어 하단 상태줄의 창 이름 클릭으로 창 전환, pane 클릭으로 포커스 이동,
# 스크롤휠로 스크롤백을 볼 수 있다.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/_resolve.sh"
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

for n in "${running[@]:1}"; do
  tmux split-window -t "=$DASH:overview" "unset TMUX; tmux attach -t '=$TEAM/$n'"
  tmux select-layout -t "=$DASH:overview" tiled >/dev/null
done
tmux select-layout -t "=$DASH:overview" tiled >/dev/null

# 에이전트별 전용 창 (탭으로 전환하며 전체 화면으로 보기)
for n in "${running[@]}"; do
  tmux new-window -t "=$DASH" -n "$n" "unset TMUX; tmux attach -t '=$TEAM/$n'"
done

# mail 창: relay.log / inbox.md 실시간 tail
tmux new-window -t "=$DASH" -n mail
tmux send-keys -t "=$DASH:mail" "tail -n 100 -f '$MAILDIR/relay.log'" Enter
tmux split-window -t "=$DASH:mail" -h
tmux send-keys -t "=$DASH:mail" "tail -n 100 -f '$MAILDIR/inbox.md'" Enter
tmux select-layout -t "=$DASH:mail" even-horizontal >/dev/null

tmux set-option -t "=$DASH" mouse on
tmux select-window -t "=$DASH:overview"

cat <<EOF
대시보드 생성됨 (팀: $TEAM, ${#running[@]}개 세션: ${running[*]})

  tmux attach -t "=$DASH"

창(탭) 목록: overview, ${running[*]}, mail
  - overview: 전체 세션 타일 뷰
  - ${running[*]}: 에이전트별 전용 전체 화면 창
  - mail: relay.log(왼쪽) / inbox.md(오른쪽) 실시간 tail

마우스 사용 가능: 하단 상태줄의 창 이름을 클릭하면 그 창으로 전환, pane을 클릭하면
포커스 이동, 스크롤휠로 스크롤백 확인이 됩니다.
주의: Ctrl-b(prefix)는 대시보드 세션이 먼저 가로챕니다 — 개별 세션에서 prefix
명령을 쓰고 싶으면 대시보드에서 나가서 tmux attach -t <세션명> 으로 개별 접속하세요.
EOF
