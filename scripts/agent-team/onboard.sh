#!/usr/bin/env bash
# 프로젝트를 훑어보고 role 파일들(main/reviewer/reviewer-sub/supervisor)의
# "## 프로젝트 컨텍스트" <TODO ...> 자리표시자를 사람과 상호작용하며 채운다.
# start.sh가 role 파일에 <TODO가 남아있을 때 자동으로 이 스크립트를 부른다.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAILDIR="${MAILDIR:-$REPO_ROOT/.agent-mail}"
ROLES_DIR="$MAILDIR/roles"

# ── 1. 자동 분석 ──────────────────────────────────────────────────────────

detect_name() {
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    grep -m1 '"name"' "$REPO_ROOT/package.json" 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
  elif [[ -f "$REPO_ROOT/pyproject.toml" ]]; then
    grep -m1 '^name' "$REPO_ROOT/pyproject.toml" 2>/dev/null | sed -E 's/name[[:space:]]*=[[:space:]]*"([^"]*)"/\1/'
  fi
}

detect_stack() {
  local hints=()
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    grep -q '"react"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("React")
    grep -q '"vue"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Vue")
    grep -q '"next"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Next.js")
    grep -q '"svelte"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Svelte")
    grep -q '"express"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Express")
    grep -q '"fastify"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Fastify")
    grep -q '"vite"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Vite")
    grep -q '"typescript"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("TypeScript")
    grep -q '"@supabase/supabase-js"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Supabase")
    grep -q '"prisma"' "$REPO_ROOT/package.json" 2>/dev/null && hints+=("Prisma")
    hints+=("Node.js")
  fi
  [[ -f "$REPO_ROOT/requirements.txt" || -f "$REPO_ROOT/pyproject.toml" ]] && hints+=("Python")
  [[ -f "$REPO_ROOT/go.mod" ]] && hints+=("Go")
  [[ -f "$REPO_ROOT/Cargo.toml" ]] && hints+=("Rust")
  [[ -f "$REPO_ROOT/pom.xml" || -f "$REPO_ROOT/build.gradle" ]] && hints+=("Java")
  ( IFS=","; echo "${hints[*]}" | sed 's/,/, /g' )
}

detect_deploy() {
  local hints=()
  [[ -f "$REPO_ROOT/netlify.toml" ]] && hints+=("Netlify")
  [[ -f "$REPO_ROOT/vercel.json" ]] && hints+=("Vercel")
  [[ -f "$REPO_ROOT/Dockerfile" ]] && hints+=("Docker")
  [[ -f "$REPO_ROOT/fly.toml" ]] && hints+=("Fly.io")
  [[ -f "$REPO_ROOT/ecosystem.config.js" || -f "$REPO_ROOT/ecosystem.config.cjs" ]] && hints+=("PM2")
  [[ -d "$REPO_ROOT/.github/workflows" ]] && hints+=("GitHub Actions")
  ( IFS=","; echo "${hints[*]}" | sed 's/,/, /g' )
}

detect_readme_summary() {
  local readme
  readme="$(find "$REPO_ROOT" -maxdepth 1 -iname "README*" 2>/dev/null | head -1)"
  [[ -n "$readme" ]] || return 0
  # 제목(# ...) 줄과 코드블록은 건너뛰고, 첫 설명 문단만 한 줄로 뽑는다.
  grep -v '^#' "$readme" | grep -v '^```' | grep -v '^\s*$' | head -2 | tr '\n' ' '
}

echo "== 프로젝트 자동 분석 (${REPO_ROOT}) =="
DETECTED_NAME="$(detect_name)"; DETECTED_NAME="${DETECTED_NAME:-$(basename "$REPO_ROOT")}"
DETECTED_STACK="$(detect_stack)"; DETECTED_STACK="${DETECTED_STACK:-알 수 없음}"
DETECTED_DEPLOY="$(detect_deploy)"; DETECTED_DEPLOY="${DETECTED_DEPLOY:-미상}"
DETECTED_README="$(detect_readme_summary || true)"

echo "이름:   $DETECTED_NAME"
echo "스택:   $DETECTED_STACK"
echo "배포:   $DETECTED_DEPLOY"
[[ -n "$DETECTED_README" ]] && echo "README: $DETECTED_README"
echo

# ── 2. 사람과 상호작용 (엔터만 치면 감지값 그대로 사용) ─────────────────────

read -rp "프로젝트 이름 [$DETECTED_NAME]: " NAME_IN
NAME="${NAME_IN:-$DETECTED_NAME}"

read -rp "스택 [$DETECTED_STACK]: " STACK_IN
STACK="${STACK_IN:-$DETECTED_STACK}"

read -rp "배포 환경 [$DETECTED_DEPLOY]: " DEPLOY_IN
DEPLOY="${DEPLOY_IN:-$DETECTED_DEPLOY}"

read -rp "이 프로젝트에서 특히 조심해야 할 부분(과거 사고 이력, 민감 영역 등, 없으면 엔터): " CAUTION

# 구현 워커(code-edit, code1, code2 ...)가 있는 팀 구성에서만 물어본다 - 그 role만 검증 명령을 필요로 한다.
BUILD_CMD=""
compgen -G "$ROLES_DIR/code*.md" >/dev/null && \
  read -rp "빌드/타입체크/테스트 명령 (없으면 엔터): " BUILD_CMD

# ── 3. role별 컨텍스트 조립 (role마다 필요한 정보량이 다르다) ───────────────

MAIN_CTX="프로젝트: $NAME
스택: $STACK
배포 환경: $DEPLOY"
[[ -n "$CAUTION" ]] && MAIN_CTX="$MAIN_CTX
주의할 점: $CAUTION"

REVIEW_CTX="스택: $STACK"
[[ -n "$CAUTION" ]] && REVIEW_CTX="$REVIEW_CTX
리뷰 시 특히 주의: $CAUTION"

SUPERVISOR_CTX="프로젝트: $NAME ($STACK)"

BUILD_CTX="스택: $STACK
검증 명령: ${BUILD_CMD:-없음 (직접 찾아서 실행할 것)}"
[[ -n "$CAUTION" ]] && BUILD_CTX="$BUILD_CTX
건드릴 때 주의: $CAUTION"

# ── 4. 각 role 파일의 <TODO ...> 블록을 교체 ────────────────────────────────

fill_role() {
  local file="$1" content="$2"
  [[ -f "$file" ]] || return 0
  grep -q "<TODO" "$file" || return 0
  python3 - "$file" "$content" <<'PYEOF'
import re, sys
path, content = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
text = re.sub(r"<TODO.*?>", lambda _m: content, text, count=1, flags=re.DOTALL)
open(path, "w", encoding="utf-8").write(text)
PYEOF
  echo "채움: $file"
}

# role 파일 목록은 팀 구성(템플릿)마다 다르므로 이름을 박아두지 않고 있는 것을 전부 훑는다.
# 모르는 이름은 리뷰어 계열로 본다 - 리뷰용 컨텍스트가 가장 무난하다.
for _role in "$ROLES_DIR"/*.md; do
  [[ -e "$_role" ]] || continue
  case "$(basename "$_role" .md)" in
    main*)      fill_role "$_role" "$MAIN_CTX" ;;   # main, main-gpt, main-claude
    supervisor) fill_role "$_role" "$SUPERVISOR_CTX" ;;
    code*)      fill_role "$_role" "$BUILD_CTX" ;;  # code-edit, code1, code2
    *)          fill_role "$_role" "$REVIEW_CTX" ;;
  esac
done

echo
echo "role 파일에 프로젝트 컨텍스트를 채웠습니다."
