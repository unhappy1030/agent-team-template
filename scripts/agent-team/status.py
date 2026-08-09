#!/usr/bin/env python3
"""각 top-level 메일 스레드의 완료 상태(수신자 전원 답장 여부)를 계산해서 출력."""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib


def main():
    team = os.environ.get("TEAM") or lib.MAILDIR.parent.name
    print(f"팀: {team}  ({lib.MAILDIR})")

    text = lib.INBOX.read_text() if lib.INBOX.exists() else ""
    messages = lib.parse_inbox(text)
    if not messages:
        print("(메일 없음)")
        return

    roots = [m for m in messages if not m.reply_to]
    for m in roots:
        replies = [r for r in messages if r.reply_to == m.id]
        replied_by = {r.sender for r in replies}
        recipients = set(m.recipients)
        missing = recipients - replied_by
        status = "DONE" if not missing else "OPEN"
        subj = m.fields.get("Subject", "").strip()
        header = f"{m.id} [{status}] {m.sender} -> {', '.join(sorted(recipients))}"
        if subj:
            header += f'  "{subj}"'
        print(header)
        if missing:
            print(f"    대기 중: {', '.join(sorted(missing))}")


if __name__ == "__main__":
    main()
