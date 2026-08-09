#!/usr/bin/env bash
# 원 메일의 발신자에게 답장을 보낸다.
# usage: reply.sh <from> <MSG-id> "<본문>"

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MAILDIR="${MAILDIR:-$(cd "$DIR/../.." && pwd)/.agent-mail}"

if [[ $# -lt 3 ]]; then
  echo "usage: reply.sh <from> <MSG-id> <body>" >&2
  exit 1
fi

python3 "$DIR/reply.py" "$1" "$2" "$3"
