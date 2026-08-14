# agent-team: TEAM/MAILDIR 환경변수 누수로 다른 팀 메일함에 오발송되는 문제

> 2026-08-13, dummy 프로젝트에서 실제로 겪은 인시던트 기록. **템플릿(`agent-team-template`)
> 자체를 고쳐야 하는 문제**라 재현 방법과 원인을 남겨둔다. `scripts/agent-team/_resolve.sh`가
> 핵심 원인 파일.

---

## 1. 증상

같은 머신에서 서로 다른 두 프로젝트의 agent-team이 동시에 떠 있을 때(`tmux ls`):

```
dummy/main, dummy/reviewer, dummy/supervisor, dummy/reviewer-sub        ← 오늘 dummy 프로젝트용으로 새로 띄운 팀
unhappy1030/main, unhappy1030/reviewer, ...                             ← 어제부터 떠있던 별개 프로젝트의 팀
```

dummy 프로젝트의 `main` 세션에서 `scripts/agent-team/send.sh main reviewer ...`를 실행했는데,
- 에러도 경고도 없이 성공(`MSG-0037` 발급)했고
- 그런데 실제로는 dummy 팀의 메일함이 아니라 **`unhappy1030` 팀(어제, 다른 프로젝트)의 전역
  메일함** `/home/unhappy1030/.agent-mail/inbox.md`에 적재됨
- `unhappy1030/reviewer` tmux 세션이 알림을 받고 답장까지 옴 — 내용이 그럴듯해서(메일 본문에
  절대경로를 적어놨기 때문에 그 세션이 파일을 직접 읽어서 답한 것으로 보임) **한눈에 이상함을
  알아채기 어려웠다.**
- 정작 이 프로젝트용으로 새로 띄운 `dummy/reviewer`는 아무 메일도 못 받음.

## 2. 원인

`scripts/agent-team/_resolve.sh`:

```bash
DEFAULT_TEAM="$(basename "$REPO_ROOT")"
TEAM="${TEAM:-$DEFAULT_TEAM}"
if [[ "$TEAM" == "$DEFAULT_TEAM" ]]; then
  MAILDIR="${MAILDIR:-$REPO_ROOT/.agent-mail}"
else
  MAILDIR="${MAILDIR:-$REPO_ROOT/.agent-mail-$TEAM}"
fi
export MAILDIR TEAM
```

`${VAR:-default}` 패턴은 **VAR가 이미 export되어 있으면 무조건 그 값을 그대로 쓴다.** 문제는:

- 예전에(다른 프로젝트에서) `TEAM=unhappy1030`, `MAILDIR=/home/unhappy1030/.agent-mail`로
  `start.sh`를 돌린 적이 있고, 그 값이 **셸/프로세스 환경에 export된 채로 남아 있었다.**
- Claude Code의 Bash 툴이 매 호출마다 새 서브프로세스를 띄우는데, 그 프로세스가 **상위 프로세스
  체인에서 저 env var를 계속 물려받는다.** `env -u MAILDIR -u TEAM`으로 직접 지워봐도, 다음
  호출에서 다시 같은 값이 나타남 — 즉 셸 rc 파일(`.bashrc`, `.zshrc` 등)에 박혀 있는 게 아니라
  **매 호출마다 상위 프로세스가 새로 주입**하는 구조라 세션 안에서 근본적으로 지울 수 없었다.
- `send.sh` → `send.py` → `lib.py`는 `_resolve.sh`를 거치지 않고, `lib.py`가 자체적으로
  `os.environ.get("MAILDIR", <repo>/.agent-mail)`로 기본값을 잡는다. 이것도 동일하게 이미
  export된 `MAILDIR`을 최우선으로 신뢰하므로 똑같이 새는 지점이다.

**결론**: "여러 프로젝트가 각자 팀 하나씩 돌린다"는 `_resolve.sh` 주석의 전제가, 실제로는
**같은 머신·같은 셸 환경 계통에서 여러 프로젝트를 오갈 때 깨진다.** env var 기반 설계라
프로젝트를 바꿔도 이전 프로젝트에서 export된 TEAM/MAILDIR이 계속 우선시된다.

## 3. 왜 위험한가

- **조용히 실패한다.** `send.sh`는 정상 종료하고 `MSG-XXXX` id도 정상 발급되어, 사람이 보기엔
  성공한 것처럼 보인다.
- **답장까지 그럴듯하게 온다.** 잘못된 팀의 reviewer가 메일 본문의 절대경로를 보고 실제 파일을
  읽어 답할 수 있어서, 받는 사람(main)도 "다른 프로젝트 팀의 응답"이라는 걸 눈치채기 어렵다.
- **메일 이력이 서로 다른 프로젝트끼리 한 inbox.md에 섞인다.** 전역 메일함
  (`/home/unhappy1030/.agent-mail`)에 폴립분할 모델 프로젝트 히스토리와 SelfSimRobot 프로젝트
  요청이 뒤섞여 쌓임.
- **정작 의도한 tmux 세션(`dummy/reviewer`)은 계속 대기 상태로 남아, 실제로는 아무 일도
  안 하고 있다는 걸 알기 어렵다.**

## 4. 당장 쓴 우회 방법 (템플릿 수정 전까지)

이 문제가 있는 세션에서는 `send.sh`/`status.sh`/`reply.sh` 호출마다 `TEAM`과 `MAILDIR`을
**명시적으로 지정**해서 env var 누수를 덮어쓴다:

```bash
TEAM=dummy MAILDIR=/home/unhappy1030/repo/dummy/.agent-mail \
  bash scripts/agent-team/send.sh main reviewer "제목" "본문"

TEAM=dummy MAILDIR=/home/unhappy1030/repo/dummy/.agent-mail \
  bash scripts/agent-team/status.sh
```

## 5. 템플릿(agent-team-template)에 반영해야 할 개선안

1. **누수 감지 가드**: `_resolve.sh`(와 `lib.py`)가 MAILDIR을 최종 확정하기 전에, 이미
   env로 들어온 `MAILDIR`이 있다면 **그 경로가 현재 `$REPO_ROOT` 하위인지 검증**한다.
   아니라면(다른 저장소를 가리키면) 경고를 찍고 무시하거나, 최소한 눈에 띄게 stderr에
   `"⚠ MAILDIR이 다른 프로젝트($MAILDIR)를 가리킵니다"`를 출력한다.
2. **매 명령마다 resolved 경로를 보여주기**: `send.sh`/`status.sh` 실행 시 결과 앞에
   `팀: $TEAM ($MAILDIR)` 한 줄을 항상 찍어서(이미 `status.sh`는 찍고 있음 — `send.sh`에도
   추가) 사람이 매번 확인할 수 있게 한다.
3. **env var 대신 프로젝트 고정 설정 파일 우선**: `$REPO_ROOT/.agent-team.conf` 같은
   저장소 안의 파일에 TEAM/MAILDIR을 기록해두고, 그 파일이 있으면 **env var보다 우선**하도록
   순서를 바꾼다. 이러면 "지금 어느 저장소에서 실행 중인가"가 "과거에 어떤 env를 export했는가"
   보다 항상 이긴다.
4. **`--team`/`--maildir` CLI 플래그 지원**: 스크립트 인자로도 넘길 수 있게 해서, 자동화
   중 확실히 지정하고 싶을 때 env var에 의존하지 않게 한다.

## 6. 재현 방법 (수정 검증용)

```bash
# 1) 프로젝트 A에서 team 시작 (TEAM=A로 export됨)
cd /path/to/A && TEAM=A scripts/agent-team/start.sh

# 2) 같은 셸 계통에서 프로젝트 B로 이동해 team 시작 (B의 send.sh가 A의 메일함으로 새는지 확인)
cd /path/to/B && scripts/agent-team/start.sh
scripts/agent-team/send.sh main reviewer "test" "test"

# 3) 확인: 메일이 B/.agent-mail/inbox.md 에 쌓였는가, 아니면 A 쪽으로 샜는가
cat /path/to/B/.agent-mail/inbox.md   # 여기 있어야 정상
cat /path/to/A/.agent-mail/inbox.md   # 여기 있으면 버그 재현
```

## 7. 후속 (2026-08-14): 5번의 개선안 1(가드)만으로는 안 막혔다

5번에서 넣은 가드(`_resolve.sh`가 MAILDIR을 REPO_ROOT 기준 계산값과 비교)는 **MAILDIR만 혼자
새는 인위적인 경우**만 막는다. 그런데 실제 재발 사례(다른 서버, home 팀을 먼저 start한 뒤 같은
셸 계통에서 `home/repo/dummy`에 `agt init`/`start`하고 "프로젝트 파악해서 메일 보내줘"라고
요청)를 그대로 재현해보니, **REPO_ROOT/TEAM/MAILDIR 셋이 항상 같이 새기 때문에** 가드가
무력화됐다:

- `start.sh`가 `tmux new-session -- claude ...`로 에이전트를 띄우는 순간, tmux는 **그 시점
  start.sh 프로세스의 환경 전체**를 세션에 스냅샷으로 물려준다 — `_resolve.sh`가 방금 계산해
  export해둔 REPO_ROOT/TEAM/MAILDIR도 그대로 포함된다.
- 그 에이전트 세션 안에서 (사람이 시키든 에이전트가 스스로든) 다른 프로젝트의
  `scripts/agent-team/send.sh`를 실행하면, `send.sh`가 `REPO_ROOT="${REPO_ROOT:-...}"`로
  **이미 상속된 값을 그대로 신뢰**한다. `_resolve.sh`가 계산하는 "정상값"도 그 잘못된
  REPO_ROOT 기준으로 계산되므로, MAILDIR도 TEAM도 서로 일관되게 틀려서 **가드가 비교할
  기준점 자체가 오염돼 있어 통과해버린다.**

**진짜 수정**: 에이전트 세션 자체가 애초에 이 3개 변수를 물려받지 않게 한다. `start.sh`의
`tmux new-session -- "${args[@]}"`를
`tmux new-session -- env -u REPO_ROOT -u TEAM -u MAILDIR "${args[@]}"`로 바꿔서, 그 세션의
최상위 프로세스(`claude`/`agy`) 자체의 `/proc/<pid>/environ`에 이 셋이 아예 없게 만든다.
실제 tmux로 검증: `env -u`로 감싼 세션의 pane_pid는 REPO_ROOT/TEAM/MAILDIR이 전혀 없고,
그 안에서 다른 프로젝트의 로컬 `send.sh`를 실행하면 정확히 그 프로젝트로 배달된다.

5번의 2(팀 표시)·3(설정 파일)·4(CLI 플래그)는 여전히 유효한 추가 개선안으로 남아있지만,
이 인시던트의 실제 재발을 막은 건 "애초에 에이전트가 이 값들을 모르게 하는" 이 수정이다.
