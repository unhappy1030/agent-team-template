# start.sh/stop.sh/dashboard.sh/status.sh가 공통으로 source한다.
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
  MAILDIR="${MAILDIR:-$REPO_ROOT/.agent-mail}"
else
  MAILDIR="${MAILDIR:-$REPO_ROOT/.agent-mail-$TEAM}"
fi
export MAILDIR TEAM
