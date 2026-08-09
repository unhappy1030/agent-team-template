#!/usr/bin/env python3
"""공유 inbox.md 파싱/작성 유틸리티. send.py/reply.py/status.py/watch.py 공용."""

import fcntl
import os
import re
import time
from pathlib import Path

_DEFAULT_MAILDIR = Path(__file__).resolve().parent.parent.parent / ".agent-mail"
MAILDIR = Path(os.environ.get("MAILDIR", str(_DEFAULT_MAILDIR)))
INBOX = MAILDIR / "inbox.md"
LOCK = MAILDIR / "inbox.md.lock"
AGENTS_CONF = MAILDIR / "agents.conf"

MSG_RE = re.compile(r"^## (MSG-\d+)\s*$")
FIELD_RE = re.compile(r"^([A-Za-z-]+):\s*(.*)$")


class Message:
    def __init__(self, msg_id, fields, body):
        self.id = msg_id
        self.fields = fields
        self.body = body

    @property
    def sender(self):
        return self.fields.get("From", "").strip()

    @property
    def recipients(self):
        to = self.fields.get("To", "")
        return [x.strip() for x in to.split(",") if x.strip()]

    @property
    def reply_to(self):
        return self.fields.get("Reply-To", "").strip() or None


def parse_inbox(text):
    messages = []
    lines = text.splitlines()
    i, n = 0, len(lines)
    while i < n:
        m = MSG_RE.match(lines[i])
        if not m:
            i += 1
            continue
        msg_id = m.group(1)
        i += 1
        fields = {}
        while i < n and FIELD_RE.match(lines[i]):
            fm = FIELD_RE.match(lines[i])
            fields[fm.group(1)] = fm.group(2)
            i += 1
        body_lines = []
        while i < n and lines[i].strip() != "---":
            body_lines.append(lines[i])
            i += 1
        if i < n and lines[i].strip() == "---":
            i += 1
        body = "\n".join(body_lines).strip("\n")
        messages.append(Message(msg_id, fields, body))
    return messages


def load_agents():
    """name -> (cli, model)"""
    agents = {}
    if AGENTS_CONF.exists():
        for line in AGENTS_CONF.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(":")
            if len(parts) < 3:
                continue
            name, cli = parts[0].strip(), parts[1].strip()
            model = ":".join(parts[2:]).strip()
            agents[name] = (cli, model)
    return agents


def depth_of(msg_id, by_id, _visited=None):
    """root(Reply-To 없음) = 0. 답장 = 1 + 부모 depth. 순환/미상 부모는 안전하게 깊게 취급."""
    if _visited is None:
        _visited = set()
    if msg_id in _visited:
        return 99
    _visited.add(msg_id)
    msg = by_id.get(msg_id)
    if msg is None:
        return 99
    if not msg.reply_to:
        return 0
    return 1 + depth_of(msg.reply_to, by_id, _visited)


def append_message(sender, recipients, subject, body, reply_to=None):
    MAILDIR.mkdir(parents=True, exist_ok=True)
    INBOX.touch(exist_ok=True)
    LOCK.touch(exist_ok=True)
    with open(LOCK, "w") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            text = INBOX.read_text() if INBOX.exists() else ""
            existing = parse_inbox(text)
            msg_id = f"MSG-{len(existing) + 1:04d}"
            ts = time.strftime("%Y-%m-%d %H:%M")
            lines = [f"## {msg_id}", f"From: {sender}", f"To: {', '.join(recipients)}"]
            if reply_to:
                lines.append(f"Reply-To: {reply_to}")
            if subject:
                lines.append(f"Subject: {subject}")
            lines.append(f"Time: {ts}")
            lines.append("")
            lines.append(body.strip())
            lines.append("")
            lines.append("---")
            lines.append("")
            block = "\n".join(lines) + "\n"
            with open(INBOX, "a") as f:
                f.write(block)
            return msg_id
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
