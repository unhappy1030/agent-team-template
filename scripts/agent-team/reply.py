#!/usr/bin/env python3
"""원 메일의 발신자에게 답장을 append. usage: reply.py <from> <MSG-id> <body>"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib


def main():
    if len(sys.argv) < 4:
        print("usage: reply.py <from> <MSG-id> <body>", file=sys.stderr)
        sys.exit(1)
    sender = sys.argv[1]
    reply_to = sys.argv[2]
    body = sys.argv[3]

    text = lib.INBOX.read_text() if lib.INBOX.exists() else ""
    messages = lib.parse_inbox(text)
    by_id = {m.id: m for m in messages}
    orig = by_id.get(reply_to)
    if orig is None:
        print(f"error: {reply_to} 를 inbox.md에서 찾을 수 없습니다", file=sys.stderr)
        sys.exit(1)

    msg_id = lib.append_message(sender, [orig.sender], None, body, reply_to=reply_to)
    print(msg_id)


if __name__ == "__main__":
    main()
