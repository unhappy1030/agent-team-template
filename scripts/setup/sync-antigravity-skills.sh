#!/usr/bin/env bash
# `npx skills add`는 스킬을 ~/.agents/skills/에 설치한다. Claude Code는 이 경로를 그대로
# 읽지만(~/.claude/skills 심볼릭 링크), Antigravity CLI(agy)는 이 경로를 읽지 않고
# ~/.gemini/config/skills/만 인식한다 (실측 확인, 2026-08). 그래서 매번 심볼릭 링크로 이어준다.

set -euo pipefail

SRC="$HOME/.agents/skills"
DST="$HOME/.gemini/config/skills"

if [[ ! -d "$SRC" ]]; then
  echo "스킬 없음: $SRC (먼저 npx skills add ... 로 설치하세요)" >&2
  exit 1
fi

mkdir -p "$DST"

count=0
for d in "$SRC"/*/; do
  name="$(basename "$d")"
  target="$DST/$name"
  [[ -e "$target" ]] && continue
  ln -s "$(readlink -f "$d")" "$target"
  count=$((count + 1))
done

echo "agy용으로 새로 연결한 스킬: ${count}개 (총 $(ls "$DST" | wc -l)개)"
