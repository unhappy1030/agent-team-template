#!/usr/bin/env python3
"""inbox.md를 폴링해서 새 메일을 발견하면 depth(Reply-To 체인 깊이)를 계산하고,
depth 0/1(1회 왕복 이내)만 수신자 tmux 세션에 '메일함 확인' 알림을 주입한다.
depth 2 이상(답장에 대한 답장)은 자동 배달하지 않고 NEEDS_ATTN을 세운다."""

import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib

PROCESSED = lib.MAILDIR / "watch.processed"
RELAY_LOG = lib.MAILDIR / "relay.log"
NEEDS_ATTN = lib.MAILDIR / "NEEDS_ATTN"
POLL_SECONDS = 2


def log(line):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    with open(RELAY_LOG, "a") as f:
        f.write(f"[{ts}] {line}\n")


def load_processed():
    if PROCESSED.exists():
        return set(x.strip() for x in PROCESSED.read_text().splitlines() if x.strip())
    return set()


def save_processed(ids):
    PROCESSED.write_text("\n".join(sorted(ids)) + "\n")


def tmux_notify(session, text):
    subprocess.run(["tmux", "send-keys", "-t", session, "-l", text], check=False)
    time.sleep(0.15)
    subprocess.run(["tmux", "send-keys", "-t", session, "Enter"], check=False)


def note_needs_attention(msg_id, reason):
    with open(NEEDS_ATTN, "a") as f:
        f.write(f"{msg_id}: {reason}\n")


def main():
    lib.MAILDIR.mkdir(parents=True, exist_ok=True)
    lib.INBOX.touch(exist_ok=True)
    processed = load_processed()
    log("watch.py 시작")

    while True:
        text = lib.INBOX.read_text() if lib.INBOX.exists() else ""
        messages = lib.parse_inbox(text)
        by_id = {m.id: m for m in messages}
        agents = lib.load_agents()

        new_ids = [m.id for m in messages if m.id not in processed]
        if new_ids:
            for msg_id in new_ids:
                m = by_id[msg_id]
                depth = lib.depth_of(msg_id, by_id)
                if depth >= 2:
                    reason = f"depth={depth} (1회 왕복 초과, 자동 배달 안 함)"
                    log(f"{msg_id} {reason}")
                    note_needs_attention(msg_id, reason)
                else:
                    for name in m.recipients:
                        if name not in agents:
                            log(f"{msg_id}: 알 수 없는 수신자 '{name}' (agents.conf에 없음)")
                            continue
                        tmux_notify(
                            name,
                            f"[MAIL] {m.sender}로부터 새 메일 도착 ({msg_id}). "
                            f".agent-mail/inbox.md 확인하세요.",
                        )
                        log(f"{msg_id} -> {name} 알림 전송 (depth={depth})")
                processed.add(msg_id)
            save_processed(processed)

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
