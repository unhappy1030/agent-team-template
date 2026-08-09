#!/usr/bin/env python3
"""새 top-level 메일을 inbox.md에 append. usage: send.py <from> <to1,to2,...> <subject> <body>"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib


def main():
    if len(sys.argv) < 5:
        print("usage: send.py <from> <to1,to2,...> <subject> <body>", file=sys.stderr)
        sys.exit(1)
    sender = sys.argv[1]
    recipients = [x.strip() for x in sys.argv[2].split(",") if x.strip()]
    subject = sys.argv[3]
    body = sys.argv[4]

    if not recipients:
        print("error: 수신자가 없습니다", file=sys.stderr)
        sys.exit(1)

    agents = lib.load_agents()
    unknown = [r for r in recipients if r not in agents]
    if unknown:
        print(f"warning: agents.conf에 없는 수신자: {', '.join(unknown)}", file=sys.stderr)

    msg_id = lib.append_message(sender, recipients, subject, body)
    print(msg_id)


if __name__ == "__main__":
    main()
