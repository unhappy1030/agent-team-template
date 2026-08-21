#!/usr/bin/env bash
# agents.conf(name:cli:model)를 읽어 에이전트별 tmux 세션을 띄우고,
# inbox.md를 감시하는 watch.py를 백그라운드로 실행한다.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$REPO_ROOT/scripts/agent-team"
source "$DIR/_resolve.sh"

mkdir -p "$MAILDIR/roles"

if [[ ! -f "$MAILDIR/agents.conf" ]]; then
  cat <<EOF >&2
agents.conf 가 없습니다: $MAILDIR/agents.conf
예시 (name:cli:model, cli는 claude 또는 antigravity):
main:claude:opus5
code-review:antigravity:gemini-3.6-flash-high
EOF
  exit 1
fi

names=()
clis=()
models=()

while IFS=: read -r name cli model || [[ -n "$name" ]]; do
  name="$(echo "$name" | xargs)"
  [[ -z "$name" || "$name" == \#* ]] && continue
  cli="$(echo "$cli" | xargs)"
  model="$(echo "$model" | xargs)"

  if tmux has-session -t "=$TEAM/$name" 2>/dev/null; then
    echo "이미 실행 중인 세션이 있습니다: $TEAM/$name (scripts/agent-team/stop.sh 로 먼저 정리하세요)" >&2
    exit 1
  fi

  names+=("$name")
  clis+=("$cli")
  models+=("$model")
done < "$MAILDIR/agents.conf"

if [[ ${#names[@]} -eq 0 ]]; then
  echo "agents.conf에 유효한 에이전트가 없습니다." >&2
  exit 1
fi

# role 파일 중 하나라도 비어있거나 <TODO가 남아있으면, 사람과 상호작용하며
# 프로젝트 컨텍스트를 채우는 onboard.sh를 자동으로 붙인다.
needs_onboarding=0
for name in "${names[@]}"; do
  role="$MAILDIR/roles/$name.md"
  { [[ ! -s "$role" ]] || grep -q "<TODO" "$role"; } && needs_onboarding=1
done

if [[ "$needs_onboarding" -eq 1 ]]; then
  if [[ -t 0 && -x "$DIR/onboard.sh" ]]; then
    echo "role 파일에 채워야 할 프로젝트 컨텍스트가 있습니다. 자동 온보딩을 시작합니다."
    echo
    "$DIR/onboard.sh"
    echo
  fi
fi

for name in "${names[@]}"; do
  role="$MAILDIR/roles/$name.md"
  if [[ ! -s "$role" ]] || grep -q "<TODO" "$role"; then
    echo "역할 파일이 비어있습니다: $role — 먼저 작성한 뒤 다시 실행하세요." >&2
    exit 1
  fi
done

# 이전 세션에서 main이 남긴 작업 컨텍스트(context.md)를 이어받을지 사람에게 묻는다.
# stop.sh는 세션만 죽일 뿐 이 파일은 남기므로, 껐다 켜도 여기서 이어붙일 수 있다.
resume_context=0
CONTEXT="$MAILDIR/context.md"
if [[ -s "$CONTEXT" ]] && printf '%s\n' "${names[@]}" | grep -qx main; then
  if [[ -t 0 ]]; then
    echo "이전 세션의 작업 컨텍스트가 있습니다: $CONTEXT"
    echo "----------------------------------------"
    head -15 "$CONTEXT"
    echo "----------------------------------------"
    read -r -p "main이 이 컨텍스트를 이어받게 할까요? [Y/n] " _ans
    if [[ "$_ans" =~ ^[Nn] ]]; then
      mv "$CONTEXT" "$CONTEXT.bak"
      echo "새로 시작합니다 (이전 내용은 $CONTEXT.bak 에 보관)."
    else
      resume_context=1
    fi
    echo
  else
    echo "이전 컨텍스트가 있지만 비대화형 실행이라 이어받지 않습니다: $CONTEXT"
  fi
fi

: > "$MAILDIR/relay.log"
rm -f "$MAILDIR/NEEDS_ATTN"
# watch.processed는 inbox.md와 짝을 이루는 "이미 알림 보낸 메일" 기록이다. inbox.md는
# 재시작해도 지우지 않으므로(메일 이력 유지), watch.processed도 여기서 지우면 안 된다 -
# 지우면 다음 watch.py가 inbox.md에 쌓인 과거 메일 전체를 새 메일로 오인해 전부 재알림한다.
touch "$MAILDIR/watch.processed"
touch "$MAILDIR/inbox.md"

for i in "${!names[@]}"; do
  name="${names[$i]}"
  cli="${clis[$i]}"
  model="${models[$i]}"
  # role 파일 원문에는 항상 ".agent-mail/..."로 적혀 있다 (템플릿 고정 문구).
  # TEAM이 기본값이 아니면 실제 메일함은 .agent-mail-$TEAM/ 이므로, 세션에 넘기기 전에
  # 실제 MAILDIR 이름으로 치환해서 에이전트가 엉뚱한(다른 팀의) 메일함을 보지 않게 한다.
  role_content="$(sed "s#\.agent-mail/#$(basename "$MAILDIR")/#g" "$MAILDIR/roles/$name.md")"

  if [[ "$name" == "main" && "$resume_context" -eq 1 ]]; then
    role_content+="

## 이전 세션 이어받기

시작하자마자 \`$(basename "$MAILDIR")/context.md\`를 읽고, 어디까지 진행됐는지 3줄 이내로
요약해 사람에게 보여준 뒤 이어서 진행할지 확인한다."
  fi

  case "$cli" in
    claude)
      args=(claude --model "$model")
      [[ "$name" != "main" ]] && args+=(--dangerously-skip-permissions)
      args+=("$role_content")
      ;;
    antigravity)
      args=(agy --model "$model")
      if [[ "$name" != "main" ]]; then
        args+=(--dangerously-skip-permissions --sandbox)
      fi
      args+=(-i "$role_content")
      ;;
    *)
      echo "알 수 없는 cli: $cli (agent: $name)" >&2
      exit 1
      ;;
  esac

  # tmux new-session은 이 순간 start.sh 프로세스의 환경을 세션에 스냅샷으로 물려준다.
  # REPO_ROOT/TEAM/MAILDIR을 그대로 두면 에이전트 프로세스 자체가 "나는 이 프로젝트"라는
  # 정보를 안고 태어나서, 나중에 그 세션 안에서 (사람이 시켜서든 스스로든) 다른 프로젝트의
  # scripts/agent-team/send.sh 등을 실행해도 ${VAR:-...} 소프트 디폴트가 이 상속값을 계속
  # 우선시해 조용히 원래 팀의 메일함으로 보낸다 (실사고: agent-team-maildir-leak.md).
  # 에이전트 세션은 이 셋을 몰라야 매번 자기가 실제로 있는 위치 기준으로 새로 계산한다.
  tmux new-session -d -s "$TEAM/$name" -c "$REPO_ROOT" -- env -u REPO_ROOT -u TEAM -u MAILDIR "${args[@]}"
  # 이 세션은 overview pane(작음)과 전용 창(큼) 양쪽에서 동시에 attach된다. 기본값인
  # window-size=latest는 둘 중 "최근에 활성화된 쪽" 크기를 따라가 버려 전용 창이 overview
  # pane 크기로 눌리고 남는 공간이 빈 칸으로 남는다. largest로 두면 항상 더 큰 쪽(전용 창)
  # 크기를 따르고, overview pane은 그 일부만 잘려 보이는 정상적인 동작이 된다.
  tmux set-option -t "=$TEAM/$name:" window-size largest
  echo "tmux 세션 시작: $TEAM/$name ($cli / $model)"
done

nohup python3 "$DIR/watch.py" >> "$MAILDIR/relay.log" 2>&1 &
echo $! > "$MAILDIR/watch.pid"

# 대시보드는 있으면 편한 보너스일 뿐이지, 여기서 실패한다고 이미 뜬 에이전트 세션까지
# 죽일 이유는 없다 (start.sh 전체가 set -e라 그냥 두면 dashboard.sh 실패가 전체를 죽인다).
"$DIR/dashboard.sh" || echo "⚠ 대시보드 생성 실패 - 에이전트 세션은 정상 기동됐습니다. 나중에 다시: scripts/agent-team/dashboard.sh" >&2

cat <<EOF

릴레이 시작됨. 팀: $TEAM   에이전트: ${names[*]}

세션 확인:     tmux ls | grep "^$TEAM/"
대시보드 보기: scripts/agent-team/view.sh   (분리: Ctrl-b d)
개별 세션 붙기: tmux attach -t "=$TEAM/<name>"
메일 보내기:   scripts/agent-team/send.sh <from> <to1,to2> "<제목>" "<본문>"
답장:          scripts/agent-team/reply.sh <from> <MSG-id> "<본문>"
상태 확인:     scripts/agent-team/status.sh
중지:          scripts/agent-team/stop.sh
로그:          $MAILDIR/relay.log
EOF
