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
  # role 파일 원문에는 항상 ".agent-mail/inbox.md"로 적혀 있다 (템플릿 고정 문구).
  # TEAM이 기본값이 아니면 실제 메일함은 .agent-mail-$TEAM/ 이므로, 세션에 넘기기 전에
  # 실제 MAILDIR 이름으로 치환해서 에이전트가 엉뚱한(다른 팀의) inbox.md를 보지 않게 한다.
  role_content="$(sed "s#\.agent-mail/inbox\.md#$(basename "$MAILDIR")/inbox.md#g" "$MAILDIR/roles/$name.md")"

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

  tmux new-session -d -s "$TEAM/$name" -c "$REPO_ROOT" -- "${args[@]}"
  echo "tmux 세션 시작: $TEAM/$name ($cli / $model)"
done

nohup python3 "$DIR/watch.py" >> "$MAILDIR/relay.log" 2>&1 &
echo $! > "$MAILDIR/watch.pid"

cat <<EOF

릴레이 시작됨. 팀: $TEAM   에이전트: ${names[*]}

세션 확인: tmux ls | grep "^$TEAM/"
붙기: tmux attach -t "=$TEAM/<name>"   (분리: Ctrl-b d)
메일 보내기: scripts/agent-team/send.sh <from> <to1,to2> "<제목>" "<본문>"
답장:       scripts/agent-team/reply.sh <from> <MSG-id> "<본문>"
상태 확인:  scripts/agent-team/status.sh
중지:       scripts/agent-team/stop.sh [--kill-sessions]
로그:       $MAILDIR/relay.log
EOF
