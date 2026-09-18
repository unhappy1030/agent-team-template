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
    전체 폴링 루프가 영구히 멈추지 않도록 타임아웃을 건다.
    콜론 없는 '=팀/이름' 형태는 tmux 3.4에서 send-keys 대상 파싱이 깨져 'can't find
    pane'으로 즉시(타임아웃 없이) 실패한다(dashboard.sh의 set-option과 같은 버그) - 그래서
    타임아웃뿐 아니라 returncode도 반드시 확인해야 한다. 안 그러면 실패한 알림도 "성공"으로
    기록돼 에이전트가 메일을 영영 못 받는다."""
    try:
        r1 = subprocess.run(
            ["tmux", "send-keys", "-t", session, "-l", text],
            check=False, timeout=NOTIFY_TIMEOUT,
        )
        time.sleep(0.15)
        r2 = subprocess.run(
            ["tmux", "send-keys", "-t", session, "Enter"],
            check=False, timeout=NOTIFY_TIMEOUT,
        )
        return r1.returncode == 0 and r2.returncode == 0
    except subprocess.TimeoutExpired:
        return False


HANDOFF = lib.MAILDIR / "handoff"


def load_handoff():
    """handoff 파일("<원래 수신자> <대신 받을 에이전트>" 한 줄)이 있으면 그 쌍을 돌려준다.
    main-gpt가 토큰 소진으로 멈추고 main-claude가 인계받은 경우처럼, 이미 보낸 메일에 대한
    답장은 reply.py가 원래 발신자(main-gpt) 앞으로 쓰므로 알림을 인계자 세션으로 돌려야
    죽은 세션에서 조용히 묻히지 않는다. 메일 내용(To:)은 그대로 두고 알림만 돌린다."""
    try:
        parts = HANDOFF.read_text().split()
    except FileNotFoundError:
        return None
    return (parts[0], parts[1]) if len(parts) >= 2 else None


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
        handoff = load_handoff()

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
                        if handoff and name == handoff[0]:
                            log(f"{msg_id}: {name} 앞 메일 알림을 인계자 {handoff[1]}에게 돌림 (handoff)")
                            name = handoff[1]
                        if name not in agents:
                            log(f"{msg_id}: 알 수 없는 수신자 '{name}' (agents.conf에 없음)")
                            continue
                        session = f"={TEAM}/{name}:"
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
