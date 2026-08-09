# agent-team-template

tmux + 파일 메일함(`inbox.md`) 기반 4인 에이전트 팀 템플릿: `main`(sonnet, 사람 대화+구현) /
`supervisor`(opus, 온디맨드 자문) / `reviewer`+`reviewer-sub`(gemini, 코드리뷰·탐색·조사, sub는
reviewer가 내부적으로 위임해 종합).

## 새 프로젝트에 설치

```bash
cp -r scripts/agent-team <target-repo>/scripts/
cp -r agent-mail-template <target-repo>/.agent-mail
```

그다음 `<target-repo>/.agent-mail/roles/*.md` 각 파일 하단의 `## 프로젝트 컨텍스트` 섹션에서
`<TODO ...>`를 실제 프로젝트 정보로 채운다 (`start.sh`는 role 파일에 `<TODO`가 남아있으면
실행을 막는다).

```bash
cd <target-repo>
scripts/agent-team/start.sh       # 4개 tmux 세션 + 메일 감시(watch.py) 시작
scripts/agent-team/dashboard.sh   # 전체 세션 한눈에 보기 (overview 타일 + 에이전트별 탭 + mail 탭)
scripts/agent-team/status.sh      # 메일 스레드 완료 상태
scripts/agent-team/stop.sh [--kill-sessions]
```

## 동작 방식

- `main`이 `send.sh`로 작업을 위임하면 `watch.py`가 2초 폴링으로 감지해 대상 tmux 세션에
  `[MAIL] ...` 문구를 타이핑해 알린다.
- 메일 스레드는 기본 1회 왕복(요청→답장)까지만 자동 배달된다. `reply.sh`의 `Reply-To` 체인
  깊이가 2 이상이면 자동 배달하지 않고 `.agent-mail/NEEDS_ATTN`에 기록한다.
- `reviewer`는 위임받은 작업을 `send.sh`로 `reviewer-sub`에게도 새 스레드로 전달(깊이 0으로
  리셋되어 자동 배달됨) → sub 답장(깊이 1) 수신 → 종합해 main의 원본 메일에 답장(깊이 1).
- 세션이 여러 클라이언트(예: 개별 attach + 대시보드의 nested attach)에 동시에 붙으면 `tmux
  send-keys`가 멈출 수 있어, `watch.py`는 알림 전송에 5초 타임아웃을 두고 실패 시
  `NEEDS_ATTN`에 기록한다.

## agents.conf 포맷

`name:cli:model`, `cli`는 `claude` 또는 `antigravity`. `main`만 사람이 승인 모드로 붙고
나머지는 자동 승인(`antigravity`는 `--sandbox`도 추가)으로 뜬다.
