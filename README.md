# agent-team-template

tmux + 파일 메일함(`inbox.md`) 기반 에이전트 팀 템플릿. 팀 구성은 여러 벌 중에 고른다
(`agent-team init --template <이름>`, 안 주면 물어본다):

| 템플릿 | 구성 |
|---|---|
| `default` (4인) | `main`(sonnet, 사람 대화+구현) / `supervisor`(opus, 온디맨드 자문) / `reviewer`+`reviewer-sub`(gemini, 코드리뷰·탐색·조사) |
| `gpt` (6인) | `main`(gpt-5.6-sol, 사람 대화+판단) / `code-edit`(gpt-5.6-luna, 구현 전담) / `supervisor`(opus) / `reviewer`(sonnet) + `sub-reviewer1`,`sub-reviewer2`(gemini) |
| `dual-main` (6인) | `main-gpt`(gpt-5.6-sol, 평소 main) / `main-claude`(opus, 평소 자문 → gpt 토큰 소진 시 main 인계) / `code1`(gpt-5.6-luna) + `code2`(sonnet, 구현) / `reviewer1`,`reviewer2`(gemini, 리뷰·검색·구조 파악, 각자 독립 답장) |

템플릿을 더 만들려면 `agent-mail-template-<이름>/` 디렉터리를 하나 더 두면 된다
(`agents.conf` + `roles/<에이전트>.md`). `init`이 자동으로 목록에 넣는다.

## 한 번에 설치 (새 머신)

```bash
./setup.sh
```

Node.js(없으면 nvm으로 설치) → claude CLI → agy(antigravity) 업데이트 → `agent-team`/`agt` 명령
등록 → codegraph 설치 + MCP 서버 등록 + 스킬 + 플러그인까지 한 번에 처리한다. 필요한 건 `curl`
뿐이고 sudo는 안 쓴다(nvm이 `~/.nvm`에 깐다). 재실행하면 그대로 업데이트 스크립트가 된다
(`npm install -g @anthropic-ai/claude-code@latest`, `agy update`, `codegraph upgrade`).

agy만은 자동 설치가 안 된다 — https://antigravity.google 에서 설치하고 `agy install`을 한 번
실행한 뒤 `./setup.sh`를 (다시) 돌리면 agy용 MCP/스킬 등록까지 끝난다. 그 전까지는 agy 관련
단계만 건너뛰고 나머지는 정상 설치된다.

## 새 프로젝트에 설치

가장 쉬운 방법은 전역 `agent-team` 명령을 한 번 설치해두고, 프로젝트마다 `init`만
실행하는 것이다:

```bash
scripts/setup/install-cli.sh   # ~/.local/bin/agent-team 심볼릭 링크 생성 (최초 1회)

cd <target-repo>
agent-team init                # .agent-mail + scripts/agent-team 복사 (팀 구성 템플릿을 물어본다)
agent-team init --template gpt # 물어보지 않고 특정 팀 구성으로
agent-team start                # role 파일의 <TODO>를 대화형으로 채운 뒤 팀 기동
```

`agent-team`은 cwd에서 위로 올라가며 `.agent-mail`을 찾아 그 프로젝트에 명령을 실행하므로(git이
`.git` 찾는 방식과 동일), 설치는 한 번만 하면 이후 어느 프로젝트에서든 그냥 `agent-team start`
처럼 쓰면 된다. 한 저장소에 팀이 여러 개면 `--team <이름>`으로 선택한다.

전역 명령 없이 수동으로 복사해도 된다:

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
scripts/agent-team/start.sh       # 필요 시 onboard.sh로 컨텍스트 채운 뒤, 4개 tmux 세션 + watch.py + dashboard까지 한 번에 기동
scripts/agent-team/view.sh        # 대시보드에 바로 attach (tmux attach 직접 안 쳐도 됨)
scripts/agent-team/dashboard.sh   # 대시보드를 다시 만들어야 할 때 (세션 재기동 등으로 새로 짜야 하면)
scripts/agent-team/status.sh      # 메일 스레드 완료 상태
scripts/agent-team/stop.sh         # watch.py + 이 팀의 tmux 세션(에이전트 전체 + dashboard) 종료
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
  TEAM=featureA scripts/agent-team/stop.sh
  ```

  `TEAM=<이름>`일 때 메일함은 `<repo>/.agent-mail-<이름>`을 쓴다(`TEAM`을 안 주는 기본 팀만
  `.agent-mail`을 그대로 쓴다). 두 팀은 세션 이름과 메일함이 완전히 분리돼 있어서 서로 간섭하지
  않는다.

**업그레이드 시 주의**: 이미 팀이 떠 있는 상태에서 스크립트만 새 버전으로 덮으면, 실행 중인
세션은 옛 이름(접두사 없음) 그대로라 `stop.sh`가 그 세션들을 못 찾는다. 새 스크립트를 받으면
먼저(구버전 스크립트로) `stop.sh`로 내린 뒤 새 스크립트로 `start.sh`를 다시 올릴 것.

## 명령어로 등록하기 (`agent-team` CLI)

`scripts/agent-team/send.sh ...`처럼 매번 상대경로를 타이핑하기 번거로우면, 얇은 디스패처를
PATH에 등록해서 어디서든 `agent-team ...`로 쓸 수 있다.

```bash
scripts/setup/install-cli.sh   # ~/.local/bin/agent-team, ~/.local/bin/agt 심볼릭 링크 생성
```

```bash
agent-team start      # dashboard까지 같이 뜬다
agent-team view       # 대시보드에 바로 attach
agent-team dashboard  # 대시보드를 새로 짜야 할 때만
agent-team status
agent-team send main reviewer "제목" "본문"
agent-team reply reviewer MSG-0001 "본문"
agent-team stop

# 같은 저장소에 팀이 여러 개면 --team으로 지정
agent-team --team featureA start
```

`agt`는 `agent-team`과 완전히 동일한 스크립트를 가리키는 짧은 별칭이다 (`agt start`, `agt --team featureA start`처럼 그대로 대체 가능).

`install-cli.sh`는 `~/.tmux.conf`에 `dashboard.sh` 창(overview/에이전트별/mail) 전환용 단축키도
추가한다(마커 주석으로 중복 추가 방지, 재실행해도 안전): `Alt+0`으로 0번 창 이동(대부분의 개인
tmux.conf에 이미 있는 `Alt+1~9`의 빠진 자리를 채움), `Ctrl+Alt+←→`로 이전/다음 창 전환(Alt+방향키는
보통 패널 이동에 이미 쓰여서 겹치지 않게 Ctrl+Alt를 씀).

`stop`은 watch.py뿐 아니라 이 팀의 tmux 세션(에이전트 전체 + dashboard가 떠 있으면 그것도)을
항상 같이 종료한다 — 예전처럼 `--kill-sessions`를 따로 줄 필요는 없다.

`scripts/agent-team/`가 대상 저장소에 복사되어 온 것이라 템플릿 쪽 버그 수정/기능 추가가
자동으로 반영되지 않는다. `upgrade`는 로컬 템플릿 클론이 있으면 `git pull`한 뒤(없으면 GitHub에서
받아서) `scripts/agent-team/`만 최신 버전으로 덮어쓴다 — `.agent-mail/roles`, `agents.conf` 같은
프로젝트별 커스터마이징은 안 건드린다.

```bash
agent-team upgrade
```

`init`의 반대(팀 메일함을 통째로 삭제)와, 삭제 후 템플릿 상태로 다시 만드는 `reinit`도 있다.
둘 다 세션이 떠 있으면 먼저 정리하고, 메일 기록·role 파일 커스터마이징이 사라지므로 팀 이름을
그대로 입력해야 진행되는 확인 절차를 거친다(`-y`/`--yes`로 건너뛸 수 있음).

```bash
agent-team uninstall            # .agent-mail(-<team>) 삭제
agent-team reinit               # uninstall + init: role 파일/agents.conf를 템플릿 기본값으로 리셋
agent-team --team featureA reinit -y
```

메일 큐만 비우고 role 파일/agents.conf는 그대로 두고 싶으면 `reset`을 쓴다
(`inbox.md`/`relay.log`/`watch.processed`/`NEEDS_ATTN` 초기화). watch.py가 떠 있으면
자동으로 재시작해서 메모리 속 처리 기록이 비워진 inbox.md와 어긋나지 않게 한다.

```bash
agent-team reset -y
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

## 작업 컨텍스트 이어받기 (context.md)

`main`은 진행 중인 작업 상태를 `.agent-mail/context.md`에 계속 갱신한다(무엇을 하는 중인지,
끝난 것/다음 할 것, 내린 결정과 이유, 관련 파일). `stop`은 이 파일을 지우지 않으므로, 팀을
껐다 켜도 하던 작업을 이어갈 수 있다.

다음 `start`에서 이 파일이 비어있지 않으면 앞부분을 보여주고 물어본다:

```
이전 세션의 작업 컨텍스트가 있습니다: /repo/.agent-mail/context.md
----------------------------------------
## 진행중
- setup.sh에 Node 설치 단계 추가
- 다음: README 갱신
----------------------------------------
main이 이 컨텍스트를 이어받게 할까요? [Y/n]
```

- **Y**(기본): main의 role 맨 뒤에 "이전 세션 이어받기" 지시가 붙어서, 뜨자마자 context.md를
  읽고 진행 상황을 요약한 뒤 이어서 할지 사람에게 확인한다.
- **n**: 이어받지 않고 새로 시작한다. 이전 내용은 `context.md.bak`으로 옮겨둔다.
- 비대화형 실행(`-t 0` 아님)에서는 묻지 않고 그냥 새로 시작한다.
- 작업이 끝나면 main이 파일을 비우므로(`: > .agent-mail/context.md`) 다음 start에서는 질문이
  뜨지 않는다.

기존에 설치해둔 프로젝트는 `agent-team upgrade`로 스크립트만 새로 받는다 — role 파일은
프로젝트별 커스터마이징이라 안 덮어쓰므로, main이 context.md를 쓰게 하려면
`agent-mail-template/roles/main.md`의 "작업 컨텍스트 유지" 절을 그 프로젝트의
`.agent-mail/roles/main.md`에 직접 복사해 넣어야 한다.

## main 인계 (`dual-main` 템플릿)

`main-gpt`의 ChatGPT 토큰이 떨어지면 `main-claude`가 main을 이어받는다. 자동 감지는 없다 —
사람이 main-claude 세션에 가서 "인계받아"라고 말하면 된다. 그러면 main-claude가:

1. `.agent-mail/handoff`에 `main-gpt main-claude` 한 줄을 쓴다. watch.py는 이 파일이 있으면
   `To: main-gpt` 메일 알림을 main-claude 세션으로 돌린다 — 인계 전에 main-gpt가 보낸 위임의
   답장은 여전히 main-gpt 앞으로 오기 때문에, 이게 없으면 멈춘 세션에서 조용히 묻힌다.
2. `context.md` + `inbox.md` + `git diff`로 상황을 파악해 5줄로 요약하고 확인받은 뒤 이어간다.

인계가 되려면 **main-gpt가 context.md를 평소에 계속 갱신해야 한다** (토큰은 예고 없이 끊기므로
끊기기 직전 정리는 불가능). 그래서 main-gpt role은 새 요청/위임 발송·답장 수신/결정/단계 완료 때마다
즉시 덮어쓰게 되어 있다. 되돌릴 때는 main-claude에게 "gpt로 돌려" → handoff 파일 삭제 +
context.md 갱신 → main-gpt 세션에서 context.md를 읽게 하면 된다. `agt start`는 handoff 파일을
지우므로 새로 띄우면 항상 main-gpt가 main이다.

`main`으로 시작하는 이름(`main`, `main-gpt`, `main-claude`)은 모두 사람이 붙는 세션으로 취급해
승인 모드로 뜬다. claude main은 `--allowedTools "Bash(agt *)"`로 팀 메일만 미리 허용한다 —
main-claude는 평소 사람이 안 보는 채로 자문 답장을 보내야 해서, 이게 없으면 `agt reply` 승인
대기에서 멈춘다.

## agents.conf 포맷

`name:cli:model`, `cli`는 `claude` / `antigravity` / `codex`. `main`만 사람이 승인 모드로 붙고
나머지는 자동 승인으로 뜬다(`antigravity`는 `--sandbox`, `codex`는
`--dangerously-bypass-approvals-and-sandbox`).

codex 워커만 샌드박스 없이 도는 이유: codex 샌드박스(`-a never -s workspace-write`)가 더 안전하지만
번들 bubblewrap이 네트워크 네임스페이스를 못 만드는 커널(라즈베리파이 등, `loopback: Failed
RTM_NEWADDR`)에서는 워커의 셸 명령이 전부 막혀 `agt reply`조차 못 한다 — 그 상태면 워커가 그냥
죽은 세션이다. bwrap이 정상 동작하는 머신이면 start.sh의 그 줄을 샌드박스 쪽으로 바꿔 쓰는 게 낫다.

codex는 model 칸을 `<모델>-<추론강도>`로 적는다(예: `gpt-5.6-sol-high`, `gpt-5.6-luna-xhigh`).
강도는 `minimal/low/medium/high/xhigh/max/ultra/persistent`이고, start.sh가 뒤쪽 강도를 떼어
`-c model_reasoning_effort=`로 넘긴다 — 슬러그에 강도를 붙인 채 보내면 ChatGPT 계정에서
`400 model is not supported`가 난다(실측, 2026-09).

codex 에이전트가 하나라도 있으면 start.sh가 `~/.codex/config.toml`에 그 저장소를
`trust_level = "trusted"`로 미리 등록한다. 안 그러면 codex가 처음 보는 디렉터리에서 "이 디렉터리를
신뢰하나?" 프롬프트를 띄우고 멈추는데, 사람이 안 보는 워커 세션은 거기서 영영 멈춘다.

## CLI 설치

`./setup.sh`가 아래를 대신 해준다 (agy만 수동).

- **claude (Claude Code)**: `npm install -g @anthropic-ai/claude-code`
- **antigravity (agy)**: https://antigravity.google 에서 설치. 설치 후 `agy install`로
  PATH/셸 설정.
- **codex (OpenAI Codex CLI)**: `npm install -g @openai/codex`. 최초 1회 `codex` 실행 →
  Sign in with ChatGPT (Plus/Pro 플랜에 포함).
- **codegraph**: `curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh`
  (이미 있으면 `codegraph upgrade`)

## MCP 서버 설정

두 CLI 모두 MCP를 지원하지만 설정 파일 위치가 다르다.

| CLI | 명령 | 설정 파일 |
|---|---|---|
| claude | `claude mcp add <name> -- <command> [args...]` | `~/.claude.json` (자동 관리) |
| agy | `agy mcp add <name> -- <command> [args...]` | `~/.gemini/config/mcp_config.json` (자동 관리) |
| codex | `codex mcp add <name> -- <command> [args...]` | `~/.codex/config.toml` (자동 관리) |

claude.ai 커넥터(Gmail/Drive/Calendar/Figma/Claude Docs)는 claude.ai 계정에 붙어 있어서
claude에서만 쓸 수 있다 — codex/agy로는 못 옮긴다. 옮겨지는 건 로컬 MCP(codegraph, playwright)뿐이다.

linux arm64(라즈베리파이 등)에는 Google Chrome 빌드가 없어서 playwright MCP가 기본값(chrome)으로는
브라우저를 못 띄운다. 설치 스크립트가 arm64면 `--browser=chromium`을 붙여 등록한다.

agy 쪽은 `~/.gemini/antigravity/mcp_config.json`처럼 그럴듯해 보이는 다른 경로가 여럿
있지만(스키마 파일은 `.antigravity-ide-server`에 있음) **실제로 읽는 건 `~/.gemini/config/
mcp_config.json` 하나뿐**이다 (실측 확인, 2026-08). `agy mcp add`가 이 파일을 갱신해주므로
직접 편집할 일은 없다 — 커맨드에 `-` 로 시작하는 인자(`--mcp` 등)가 있으면 이름 뒤에 `--`를
꼭 붙여야 한다.

이 파일 하나면 agy·claude 양쪽 다 커버되지 않는다 — **claude는 별도로
`claude mcp add`가 필요하다.** 둘 다 등록해야 두 CLI 모두에서 같은 MCP 서버를 쓸 수 있다.

확인: `agy -p "사용 가능한 MCP 서버 목록을 알려줘" --dangerously-skip-permissions`

## 스킬(Skill) 설정

`./setup.sh`(내부적으로 `scripts/setup/install_skill_mcp_plugin.sh`)가 지금 쓰는 스킬 목록을
그대로 설치하고 아래 동기화까지 해준다. 개별로 추가할 때는 [skills CLI](https://skills.sh)
(`npx skills`)로 두 CLI에 한 번에 설치한다:

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

**codex는 반대로 `~/.agents/skills/`를 직접 읽는다**(사용자 스킬 위치, 실측 2026-09). 그래서
위 설치만으로 codex에도 다 보이고 동기화가 필요 없다. `-a codex`를 추가하면 같은 스킬이 두 곳에서
잡혀 중복으로 뜨므로 넣지 않는다.

codex에 없는 도구를 전제로 한 스킬 11개는 설치 스크립트가 **codex에서만** 꺼둔다
(`~/.codex/config.toml`의 `[[skills.config]] enabled = false`, claude/agy는 그대로):
context-mode 계열 9개(`ctx_*` MCP 도구 전제), `caveman-stats`(Claude 세션 로그를 읽음),
`cavecrew`(Claude Agent 툴 전제). codex는 스킬 목록에 컨텍스트의 2%만 쓰므로 못 쓰는 스킬이
자리만 차지하지 않게 하려는 것이다. context-mode를 codex에 설치했다면
(`codex plugin marketplace add mksglu/context-mode`) 스크립트의 `CODEX_OFF_SKILLS`에서 빼면 된다.

`grill-me`, `handoff`처럼 `disable-model-invocation: true`인 스킬은 모델이 스스로 고르는 목록에는
안 나오고 사람이 직접 부를 때만 쓰인다 — codex도 Claude와 똑같이 동작한다.

확인: `codex exec "사용 가능한 스킬 이름만 쉼표로 나열해줘"`

설치되는 스킬은 각자 다른 사람이 만든 외부 코드/프롬프트다. `npx skills add`는 설치 시
Gen/Socket/Snyk 3종 보안 스캔 결과를 보여주는데, 코드를 직접 실행하는 유형의 스킬
(브라우저 자동화 등)은 "임의 코드 실행 가능"이라는 이유만으로도 Critical/High로 뜰 수 있다
— Bash 툴 자체가 이미 가진 것과 같은 종류의 권한이라는 뜻이지, 그 자체로 악성이라는 뜻은
아니다. 그래도 설치 전 `-l`(`--list`)로 목록만 먼저 보거나, 설치 후 `~/.agents/skills/<name>/
SKILL.md`를 한 번 읽어보는 걸 권장한다.
