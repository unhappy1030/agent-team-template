#!/usr/bin/env bash
# 메일 스레드 완료 상태를 조회한다.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$DIR/../.." && pwd)}"
source "$DIR/_resolve.sh"

python3 "$DIR/status.py"
