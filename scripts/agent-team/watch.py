#!/usr/bin/env python3
"""inbox.md를 폴링해서 새 메일을 발견하면 depth(Reply-To 체인 깊이)를 계산하고,
depth 0/1(1회 왕복 이내)만 수신자 tmux 세션에 '메일함 확인' 알림을 주입한다.
depth 2 이상(답장에 대한 답장)은 자동 배달하지 않고 NEEDS_ATTN을 세운다."""

import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib

# start.sh가 TEAM을 export해서 넘겨준다. 없으면(예: watch.py를 단독 실행) 메일함의
# 상위 디렉터리 이름(대개 저장소 이름)으로 대체한다 - tmux 세션 이름 접두사와 동일한 규칙.
TEAM = os.environ.get("TEAM") or lib.MAILDIR.parent.name

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


NOTIFY_TIMEOUT = 5


def tmux_notify(session, text):
    """tmux send-keys가 멈춰도(예: 세션에 클라이언트가 여럿 붙어 응답이 안 오는 경우)
    전체 폴링 루프가 영구히 멈추지 않도록 타임아웃을 건다."""
    try:
        subprocess.run(
            ["tmux", "send-keys", "-t", session, "-l", text],
            check=False, timeout=NOTIFY_TIMEOUT,
        )
        time.sleep(0.15)
        subprocess.run(
            ["tmux", "send-keys", "-t", session, "Enter"],
            check=False, timeout=NOTIFY_TIMEOUT,
        )
        return True
    except subprocess.TimeoutExpired:
        return False


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
                        session = f"={TEAM}/{name}"
                        ok = tmux_notify(
                            session,
                            f"[MAIL] {m.sender}로부터 새 메일 도착 ({msg_id}). "
                            f"{lib.MAILDIR.name}/inbox.md 확인하세요.",
                        )
                        if ok:
                            log(f"{msg_id} -> {session} 알림 전송 (depth={depth})")
                        else:
                            reason = f"{session}에게 tmux send-keys 타임아웃 (자동 배달 실패)"
                            log(f"{msg_id} {reason}")
                            note_needs_attention(msg_id, reason)
                processed.add(msg_id)
            save_processed(processed)

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
