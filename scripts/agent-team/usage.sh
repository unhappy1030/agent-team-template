#!/usr/bin/env bash
# 에이전트별 토큰 사용량과 각 CLI의 한도(리셋까지 남은 시간)를 한 번에 본다.
# usage: agent-team usage
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$DIR/../.." && pwd)}"
source "$DIR/_resolve.sh"

exec python3 "$DIR/usage.py" "$@"
