#!/usr/bin/env bash
# 새 top-level 메일을 inbox.md에 보낸다.
# usage: send.sh <from> <to1,to2,...> "<제목>" "<본문>"

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MAILDIR="${MAILDIR:-$(cd "$DIR/../.." && pwd)/.agent-mail}"

if [[ $# -lt 4 ]]; then
  echo "usage: send.sh <from> <to1,to2,...> <subject> <body>" >&2
  exit 1
fi

python3 "$DIR/send.py" "$1" "$2" "$3" "$4"
