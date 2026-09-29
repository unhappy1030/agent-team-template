#!/usr/bin/env bash
# 팀 구성(agents.conf + roles/)만 다른 템플릿으로 바꾼다. 메일 기록(inbox.md, watch.processed)은
# 그대로 둔다 — reinit은 메일함을 통째로 지우므로, 하던 일을 유지한 채 팀만 갈아끼울 때 쓴다.
#
# - 떠 있는 팀은 먼저 내린다 (세션 구성이 바뀌므로). 끝나면 agt start로 다시 띄운다.
# - 이전 agents.conf/roles/context.md는 prev-team/ 에 한 벌 보관한다 (다시 switch하면 덮어씀).
# - context.md는 새 팀 형식으로 다시 만든다: main이 여럿이면 "## <main 이름>" 빈 섹션들, 하나면 빈 파일.
#   이전 내용을 반영할지는 묻는다(기본 Y, --context/--no-context로 지정). 반영하면 이전 파일의
#   "## <main>" 섹션은 같은 이름의 새 main에게, 섹션이 없거나 이름이 안 맞는 부분은 첫 main에게 간다
#   (같은 내용을 두 main에 복사하면 둘이 같은 일을 이어받으므로 복사하지 않는다).
# - role 파일에 채워둔 "## 프로젝트 컨텍스트"는 새 role로 옮긴다: 같은 이름의 옛 role이 있으면 그것,
#   없으면 같은 계열(main* / code* / supervisor / 그 외=리뷰어)의 옛 role에서. 못 찾으면 <TODO>로
#   남아 다음 start에서 onboard.sh가 묻는다.
# usage: agent-team switch [--template <이름>] [--context|--no-context] [-y|--yes]
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="$REPO_ROOT/scripts/agent-team"
source "$DIR/_resolve.sh"

yes=0
carry=""
init_args=()
for a in "$@"; do
  case "$a" in
    -y|--yes) yes=1 ;;
    --context) carry=1 ;;
    --no-context) carry=0 ;;
    *) init_args+=("$a") ;;
  esac
done

if [[ ! -d "$MAILDIR" ]]; then
  echo "메일함이 없습니다: $MAILDIR (처음이면 agent-team init)" >&2
  exit 1
fi

if tmux ls -F '#S' 2>/dev/null | grep -q "^$TEAM/" && [[ "$yes" -ne 1 ]]; then
  echo "팀 $TEAM 이 실행 중입니다. 팀 구성을 바꾸려면 세션을 모두 내려야 합니다 (메일 기록은 유지)."
  if [[ ! -t 0 ]]; then
    echo "비대화형 실행이라 확인할 수 없습니다. -y/--yes를 주고 다시 실행하세요." >&2
    exit 1
  fi
  read -r -p "내리고 계속할까요? (y/N) " confirm
  [[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "취소됨." >&2; exit 1; }
fi
"$DIR/stop.sh" >/dev/null 2>&1 || true

prev="$MAILDIR/prev-team"
rm -rf "$prev" && mkdir -p "$prev"
cp -r "$MAILDIR/roles" "$MAILDIR/agents.conf" "$prev/" 2>/dev/null || true
cp "$MAILDIR/context.md" "$prev/" 2>/dev/null || true

# init.sh는 이 스크립트 옆의 것을 쓴다 - 프로젝트에 복사된 scripts/agent-team은 upgrade 전이면
# SWITCH 모드를 모르는 옛 init.sh일 수 있다 (agt switch는 디스패처가 템플릿 쪽 switch.sh를 부른다).
SWITCH=1 TEAM="$TEAM" "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" "$REPO_ROOT" ${init_args[@]+"${init_args[@]}"}

# 옛 main이 남긴 인계 우회는 새 팀 구성에선 의미가 없다 (start.sh도 지우지만 미리 정리).
rm -f "$MAILDIR/handoff"

# 이전 context.md를 새 main들에 반영할지 (내용이 있을 때만 묻는다)
if [[ -s "$prev/context.md" && -z "$carry" ]]; then
  carry=1
  if [[ -t 0 ]]; then
    echo "이전 작업 컨텍스트 (prev-team/context.md):"
    echo "----------------------------------------"
    head -15 "$prev/context.md"
    echo "----------------------------------------"
    read -r -p "새 팀의 main들에 반영할까요? [Y/n] " _ans
    [[ "$_ans" =~ ^[Nn] ]] && carry=0
  fi
fi

mains="$(grep -v -e '^#' -e '^[[:space:]]*$' "$MAILDIR/agents.conf" | cut -d: -f1 | tr -d ' ' | grep '^main' || true)"
python3 - "$prev/context.md" "$MAILDIR/context.md" "${carry:-0}" $mains <<'EOF'
import pathlib, re, sys
old_path, new_path, carry, mains = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3] == "1", sys.argv[4:]
old = old_path.read_text(encoding="utf-8") if carry and old_path.exists() else ""

# 이전 파일을 "## <main>" 섹션별로 쪼갠다. 섹션 앞(또는 섹션 없는 파일 전체)은 이름 없는 덩어리.
parts, name, buf = {}, None, []
for line in old.splitlines():
    m = re.fullmatch(r"## (main\S*)\s*", line)
    if m:
        parts.setdefault(name, []).extend(buf); name, buf = m.group(1), []
    else:
        buf.append(line)
parts.setdefault(name, []).extend(buf)

body = {m: [] for m in mains}
for k, lines in parts.items():
    if not "".join(lines).strip():
        continue
    if k in body:
        body[k] += lines
    elif mains:
        # 이름 없는 덩어리이거나 새 팀에 없는 main의 섹션 → 첫 main에게 (출처 표시)
        body[mains[0]] += ([f"(이전 {k} 섹션)"] if k else []) + lines

if len(mains) > 1:
    text = "\n\n".join("\n".join([f"## {m}"] + [l for l in body[m]]).rstrip() for m in mains) + "\n"
else:
    text = "\n".join(body[mains[0]]).strip() + "\n" if mains and "".join(body[mains[0]]).strip() else ""
new_path.write_text(text, encoding="utf-8")
got = [m for m in mains if "".join(body[m]).strip()]
print(f"  context.md: 새 팀 형식으로 세팅" + (f", 이전 내용 반영 → {', '.join(got)}" if got else " (이전 내용 반영 안 함)"))
EOF

python3 - "$prev/roles" "$MAILDIR/roles" <<'EOF'
import pathlib, sys
H = "## 프로젝트 컨텍스트"
old_dir, new_dir = map(pathlib.Path, sys.argv[1:])

def family(name):
    for p in ("main", "code", "supervisor"):
        if name.startswith(p):
            return p
    return "review"

def ctx(path):
    # 제목 줄 다음부터 끝까지가 컨텍스트 본문 (모든 템플릿에서 이 절이 맨 끝이다)
    text = path.read_text(encoding="utf-8")
    i = text.find(H)
    if i < 0:
        return None
    body = text[text.index("\n", i) + 1:] if "\n" in text[i:] else ""
    return None if "<TODO" in body or not body.strip() else body

old = {p.stem: ctx(p) for p in old_dir.glob("*.md")} if old_dir.is_dir() else {}
old = {k: v for k, v in old.items() if v}
for new in sorted(new_dir.glob("*.md")):
    body = old.get(new.stem) or next((v for k, v in old.items() if family(k) == family(new.stem)), None)
    text = new.read_text(encoding="utf-8")
    i = text.find(H)
    if body is None or i < 0:
        print(f"  {new.name}: 컨텍스트 없음 → 다음 start에서 온보딩")
        continue
    new.write_text(text[:text.index("\n", i) + 1] + body, encoding="utf-8")
    print(f"  {new.name}: 프로젝트 컨텍스트 옮김")
EOF

start_cmd="agent-team start"
[[ "$TEAM" != "$(basename "$REPO_ROOT")" ]] && start_cmd="agent-team --team $TEAM start"
echo "이전 구성(agents.conf, roles, context.md)은 $prev 에 보관했습니다. 메일 기록은 그대로입니다."
echo "다음: $start_cmd"
