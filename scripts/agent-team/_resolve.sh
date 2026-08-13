# start.sh/stop.sh/dashboard.sh/status.sh/send.sh/reply.sh가 공통으로 source한다.
# 호출 스크립트가 REPO_ROOT를 먼저 계산해둔 뒤 이 파일을 source하면 TEAM/MAILDIR를 확정해준다.
#
# 여러 프로젝트에서 각자 팀 하나씩 돌리는 경우(기본): TEAM을 안 주면 저장소 폴더명이
# 자동으로 팀 이름이 되고, MAILDIR는 기존과 동일하게 <repo>/.agent-mail 그대로 쓴다
# (하위 호환 - 메일함 경로도 안 바뀌고, tmux 세션 이름에만 팀 접두사가 붙는다).
#
# 같은 저장소 안에서 팀을 여러 개 굴리는 경우: TEAM=<이름>을 명시하면
# MAILDIR는 <repo>/.agent-mail-<이름>을 쓴다 (agent-mail-template을 그 이름으로
# 한 번 더 복사해서 준비해둬야 한다).
DEFAULT_TEAM="$(basename "$REPO_ROOT")"
TEAM="${TEAM:-$DEFAULT_TEAM}"
if [[ "$TEAM" == "$DEFAULT_TEAM" ]]; then
  _computed_maildir="$REPO_ROOT/.agent-mail"
else
  _computed_maildir="$REPO_ROOT/.agent-mail-$TEAM"
fi

# 누수 가드: tmux 세션은 생성 시점 셸 환경을 그대로 물려받으므로, 예전에(다른 프로젝트/팀
# 에서) export된 MAILDIR이 이후 그 세션 안 모든 프로세스에 계속 남아있을 수 있다. 이미
# env로 들어온 MAILDIR이 지금 저장소 기준으로 계산한 값과 다르면, 조용히 그 값을 신뢰하지
# 않고 경고를 찍은 뒤 현재 저장소 기준 값으로 되돌린다.
# (실사고 기록: agent-team-maildir-leak.md - 다른 프로젝트의 메일함으로 조용히 오발송됨)
if [[ -n "${MAILDIR:-}" && "$MAILDIR" != "$_computed_maildir" ]]; then
  echo "⚠ MAILDIR 환경변수($MAILDIR)가 현재 저장소($REPO_ROOT, 팀: $TEAM)와 다른 곳을 가리킵니다." >&2
  echo "  과거 다른 프로젝트/팀에서 export된 값이 새어 들어온 것으로 보여 무시하고 $_computed_maildir 를 씁니다." >&2
  echo "  정말 이 경로를 쓰려는 거라면 이 저장소 소속 경로로 다시 지정하세요." >&2
  unset MAILDIR
fi

MAILDIR="${MAILDIR:-$_computed_maildir}"
unset _computed_maildir
export MAILDIR TEAM
