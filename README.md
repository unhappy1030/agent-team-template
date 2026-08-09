# agent-team-template

tmux + 파일 메일함(`inbox.md`) 기반 4인 에이전트 팀 템플릿: `main`(sonnet, 사람 대화+구현) /
`supervisor`(opus, 온디맨드 자문) / `reviewer`+`reviewer-sub`(gemini, 코드리뷰·탐색·조사, sub는
reviewer가 내부적으로 위임해 종합).

## 새 프로젝트에 설치

```bash
cp -r scripts/agent-team <target-repo>/scripts/
cp -r agent-mail-template <target-repo>/.agent-mail
```

`<target-repo>/.agent-mail/roles/*.md` 각 파일 하단의 `## 프로젝트 컨텍스트` 섹션에는
`<TODO ...>` 자리표시자가 남아있다. `start.sh`를 처음 실행하면 role 파일에 `<TODO`가 남은
경우 `onboard.sh`가 자동으로 붙어 프로젝트를 훑어보고(package.json/README/배포 설정 등) 감지한
값을 사람에게 보여준 뒤, 이름/스택/배포 환경/주의할 점을 몇 가지 물어 각 role 파일의
`<TODO ...>`를 채운다. 직접 편집하고 싶으면 `start.sh`를 실행하기 전에 role 파일을 미리 채워도
된다(그러면 onboard.sh는 건너뛴다).

**중요**: `.agent-mail/`, `scripts/agent-team/`, `.github/hooks/`는 프로젝트 앱 코드가 아니라
로컬 팀 운영 도구이므로, 설치 후 대상 저장소의 `.gitignore`에 이 세 경로를 추가하는 걸 권장한다.

```bash
cd <target-repo>
scripts/agent-team/start.sh       # 필요 시 onboard.sh로 컨텍스트 채운 뒤, 4개 tmux 세션 + 메일 감시(watch.py) 시작
scripts/agent-team/dashboard.sh   # 전체 세션 한눈에 보기 (overview 타일 + 에이전트별 탭 + mail 탭)
scripts/agent-team/status.sh      # 메일 스레드 완료 상태
scripts/agent-team/stop.sh [--kill-sessions]
```

## 여러 팀 동시 운용 (멀티 팀)

tmux 세션 이름은 머신 전체에서 하나의 전역 이름공간이라, 아무 조치 없이 서로 다른 저장소에서
동시에 `start.sh`를 실행하면 `main` 같은 세션 이름이 그대로 충돌한다. (반면 `.agent-mail/`
자체는 저장소별로 이미 분리돼 있어서 메일함이 섞이는 일은 원래도 없었다.)

그래서 모든 tmux 세션 이름 앞에 **팀 이름**을 접두사로 붙인다(`<팀>/main`, `<팀>/reviewer` 등).
`TEAM` 환경변수를 안 주면 저장소 폴더명이 자동으로 팀 이름이 된다 — 기존 설치도 업그레이드
즉시 자동으로 네임스페이스가 적용되고, 메일함 경로(`.agent-mail`)도 그대로라 별도 마이그레이션이
필요 없다.

- **서로 다른 프로젝트에서 각자 한 팀씩** (가장 흔한 경우): 아무것도 안 해도 된다. 저장소 폴더명이
  다르면 팀 이름도 자동으로 달라져서 세션이 안 겹친다.
- **같은 저장소 안에서 팀을 여러 개**: `agent-mail-template`을 팀 이름을 붙인 다른 디렉터리로
  한 번 더 복사하고, `TEAM` 환경변수로 실행한다.

  ```bash
  cp -r agent-mail-template <target-repo>/.agent-mail-featureA
  cd <target-repo>
  TEAM=featureA scripts/agent-team/start.sh
  TEAM=featureA scripts/agent-team/dashboard.sh
  TEAM=featureA scripts/agent-team/stop.sh --kill-sessions
  ```

  `TEAM=<이름>`일 때 메일함은 `<repo>/.agent-mail-<이름>`을 쓴다(`TEAM`을 안 주는 기본 팀만
  `.agent-mail`을 그대로 쓴다). 두 팀은 세션 이름과 메일함이 완전히 분리돼 있어서 서로 간섭하지
  않는다.

**업그레이드 시 주의**: 이미 팀이 떠 있는 상태에서 스크립트만 새 버전으로 덮으면, 실행 중인
세션은 옛 이름(접두사 없음) 그대로라 `stop.sh --kill-sessions`가 그 세션들을 못 찾는다. 새
스크립트를 받으면 먼저 `stop.sh --kill-sessions`로 내린 뒤 `start.sh`로 다시 올릴 것.

## 명령어로 등록하기 (`agent-team` CLI)

`scripts/agent-team/send.sh ...`처럼 매번 상대경로를 타이핑하기 번거로우면, 얇은 디스패처를
PATH에 등록해서 어디서든 `agent-team ...`로 쓸 수 있다.

```bash
scripts/setup/install-cli.sh   # ~/.local/bin/agent-team 심볼릭 링크 생성
```

```bash
agent-team start
agent-team dashboard
agent-team status
agent-team send main reviewer "제목" "본문"
agent-team reply reviewer MSG-0001 "본문"
agent-team stop --kill-sessions

# 같은 저장소에 팀이 여러 개면 --team으로 지정
agent-team --team featureA start
```

`agent-team`은 실행된 위치(cwd)에서 위로 올라가며 `.agent-mail`(또는 `.agent-mail-<팀>`)을
찾아 그 팀에게 위임할 뿐인 얇은 래퍼다(git이 `.git`을 찾는 방식과 동일) — CLI 프레임워크가
아니라 기존 `.sh` 스크립트에 `exec`으로 넘겨주는 30줄짜리 스크립트다. 저장소 폴더 안 어디서
실행해도 되고, 같은 저장소에 팀이 둘 이상이면 `--team`을 안 줬을 때 어떤 팀들이 있는지 알려주고
멈춘다. 기존 `scripts/agent-team/*.sh`는 그대로 남아있으니 디스패처 없이 예전처럼 써도 된다.

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

## CLI 설치

- **claude (Claude Code)**: `npm install -g @anthropic-ai/claude-code`
- **antigravity (agy)**: https://antigravity.google 에서 설치. 설치 후 `agy install`로
  PATH/셸 설정.

## MCP 서버 설정

두 CLI 모두 MCP를 지원하지만 설정 파일 위치가 다르다.

| CLI | 명령 | 설정 파일 |
|---|---|---|
| claude | `claude mcp add <name> -- <command> [args...]` | `~/.claude.json` (자동 관리) |
| agy | 직접 JSON 편집 | `~/.gemini/config/mcp_config.json` |

agy 쪽은 `~/.gemini/antigravity/mcp_config.json`처럼 그럴듯해 보이는 다른 경로가 여럿
있지만(스키마 파일은 `.antigravity-ide-server`에 있음) **실제로 읽는 건 `~/.gemini/config/
mcp_config.json` 하나뿐**이다 (실측 확인, 2026-08). 포맷은 Claude Desktop과 동일한
`mcpServers` 객체:

```json
{
  "mcpServers": {
    "codegraph": { "command": "/path/to/codegraph", "args": ["serve", "--mcp"] },
    "playwright": { "command": "npx", "args": ["-y", "@playwright/mcp@latest"] }
  }
}
```

이 파일 하나면 agy·claude 양쪽 다 커버되지 않는다 — **claude는 별도로
`claude mcp add`가 필요하다.** 둘 다 등록해야 두 CLI 모두에서 같은 MCP 서버를 쓸 수 있다.

확인: `agy -p "사용 가능한 MCP 서버 목록을 알려줘" --dangerously-skip-permissions`

## 스킬(Skill) 설정

[skills CLI](https://skills.sh) (`npx skills`)로 두 CLI에 한 번에 설치한다:

```bash
npx skills add <owner>/<repo> -g -a claude-code antigravity-cli -y
# 저장소에 스킬이 여러 개면: -s <skill-이름1> <skill-이름2>
```

**함정**: 이 명령은 스킬을 `~/.agents/skills/`에 설치하고 Claude Code용으로는
`~/.claude/skills/`에 심볼릭 링크를 만들어준다. 여기까지는 자동으로 잘 된다. 하지만
**agy(Antigravity CLI)는 `~/.agents/skills/`를 읽지 않는다** — `~/.gemini/config/skills/`만
인식한다(실측 확인, 2026-08). 그래서 설치 후 한 번 동기화가 필요하다:

```bash
scripts/setup/sync-antigravity-skills.sh
```

새 스킬을 추가로 설치할 때마다 다시 실행하면 된다 (이미 연결된 건 건너뛴다).

확인: `agy -p "사용 가능한 스킬 목록을 알려줘" --dangerously-skip-permissions`

설치되는 스킬은 각자 다른 사람이 만든 외부 코드/프롬프트다. `npx skills add`는 설치 시
Gen/Socket/Snyk 3종 보안 스캔 결과를 보여주는데, 코드를 직접 실행하는 유형의 스킬
(브라우저 자동화 등)은 "임의 코드 실행 가능"이라는 이유만으로도 Critical/High로 뜰 수 있다
— Bash 툴 자체가 이미 가진 것과 같은 종류의 권한이라는 뜻이지, 그 자체로 악성이라는 뜻은
아니다. 그래도 설치 전 `-l`(`--list`)로 목록만 먼저 보거나, 설치 후 `~/.agents/skills/<name>/
SKILL.md`를 한 번 읽어보는 걸 권장한다.
