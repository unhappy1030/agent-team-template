#!/usr/bin/env python3
"""팀 에이전트별 토큰 사용량 요약 (dashboard의 usage 창이 주기적으로 실행한다).

출처 - 별도 도구 없이 각 CLI가 남기는 세션 로그를 그대로 읽는다:
  claude: ~/.claude/projects/<프로젝트>/<세션>.jsonl 의 message.usage
  codex : ~/.codex/sessions/<날짜>/rollout-*.jsonl 의 thread_token_usage + rate_limits
          (rate_limits에 한도 사용률/리셋 시각이 들어있다 - main-gpt 인계 시점 판단용)
  agy   : 사용량 로그를 남기지 않아 표시할 값이 없다.

에이전트-세션 짝짓기: 세션의 첫 user 메시지가 role 파일 원문이라 "# <이름> 역할 정의"로 알아낸다.
같은 이름의 세션이 여러 개면 가장 최근 것을 쓴다.
"""

import json
import os
import re
import sys
import time
import unicodedata
import urllib.request
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib

REPO_ROOT = Path(os.environ.get("REPO_ROOT") or lib.MAILDIR.parent).resolve()
TEAM = os.environ.get("TEAM") or lib.MAILDIR.parent.name
ROLE_RE = re.compile(r"#\s*([A-Za-z0-9_.-]+)\s*역할 정의")
MAX_AGE_SEC = 36 * 3600  # 이보다 오래된 세션 로그는 이번 팀 것이 아니라고 본다
SCAN_LINES = 120  # 앞부분만 읽어 cwd/역할을 찾는다 (로그가 커도 빨리 끝나게)


def recent_files(root, pattern):
    now = time.time()
    if not root.is_dir():
        return []
    return [p for p in root.glob(pattern)
            if p.is_file() and now - p.stat().st_mtime < MAX_AGE_SEC]


def identify(path):
    """(에이전트 이름, cwd) - 앞부분만 훑어서 찾는다. 못 찾으면 (None, None)."""
    name = cwd = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            if i >= SCAN_LINES or (name and cwd):
                break
            if not cwd:
                m = re.search(r'"cwd"\s*:\s*"([^"]+)"', line)
                if m:
                    cwd = m.group(1)
            if not name:
                m = ROLE_RE.search(line)
                if m:
                    name = m.group(1)
    return name, cwd


def claude_usage(path):
    """input/output/cache 합계. 누적값이 아니라 메시지마다 나오므로 더한다."""
    tot = dict(inp=0, out=0, cache_r=0, cache_w=0)
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                u = (json.loads(line).get("message") or {}).get("usage") or {}
            except json.JSONDecodeError:
                continue
            tot["inp"] += u.get("input_tokens", 0)
            tot["out"] += u.get("output_tokens", 0)
            tot["cache_r"] += u.get("cache_read_input_tokens", 0)
            tot["cache_w"] += u.get("cache_creation_input_tokens", 0)
    return tot, None


def codex_usage(path):
    """thread_token_usage는 스레드 누적값이라 마지막 것만 쓴다. rate_limits도 마지막 것."""
    tot = dict(inp=0, out=0, cache_r=0, cache_w=0)
    limits = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"thread_token_usage"' not in line and '"rate_limits"' not in line:
                continue
            try:
                payload = json.loads(line).get("payload") or {}
            except json.JSONDecodeError:
                continue
            u = payload.get("thread_token_usage") or {}
            if u:
                tot = dict(inp=u.get("input_tokens", 0), out=u.get("output_tokens", 0),
                           cache_r=u.get("cached_input_tokens", 0),
                           cache_w=u.get("cache_write_input_tokens", 0))
            rl = payload.get("rate_limits")
            if rl:
                limits = rl
    return tot, limits


def collect():
    """{에이전트 이름: (사용량, 한도, 로그 mtime)} - 이 저장소에서 돈 세션만."""
    found = {}
    sources = [
        (Path.home() / ".claude" / "projects", "*/*.jsonl", claude_usage),
        (Path.home() / ".codex" / "sessions", "*/*/*/rollout-*.jsonl", codex_usage),
    ]
    for root, pattern, parse in sources:
        for path in recent_files(root, pattern):
            name, cwd = identify(path)
            if not name or not cwd:
                continue
            if Path(cwd).resolve() != REPO_ROOT:
                continue
            mtime = path.stat().st_mtime
            if name in found and found[name][2] >= mtime:
                continue
            found[name] = (*parse(path), mtime)
    return found



# ── 실시간 한도 조회 ────────────────────────────────────────────────────────
# 각 CLI가 로컬에 남기는 값은 갱신이 들쭉날쭉하다(claude의 ~/.claude.json 캐시는 며칠 전 값으로
# 멈춰 있기도 하다). 그래서 각 CLI가 이미 저장해둔 자기 자격증명으로 해당 서비스의 공식 사용량
# 엔드포인트에 직접 묻는다 - 사용자 본인 계정의 사용량이고, 제3자로 나가는 요청은 없다.
# 대시보드가 30초마다 다시 그리므로 결과는 CACHE_TTL초 동안 파일에 캐시한다.
CACHE_TTL = 120
CACHE = lib.MAILDIR / "usage-limits.json"


def http_json(url, headers, timeout=15):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def claude_limits():
    """~/.claude/.credentials.json의 OAuth 토큰으로 5시간/7일 사용률을 받아온다."""
    cred = json.loads((Path.home() / ".claude" / ".credentials.json").read_text())
    tok = (cred.get("claudeAiOauth") or {}).get("accessToken")
    if not tok:
        raise RuntimeError("claude OAuth 토큰 없음")
    d = http_json("https://api.anthropic.com/api/oauth/usage",
                  {"Authorization": f"Bearer {tok}",
                   "anthropic-beta": "oauth-2025-04-20",
                   "User-Agent": "agent-team-usage"})
    out = {}
    for key, label in (("five_hour", "5시간"), ("seven_day", "7일")):
        w = d.get(key) or {}
        if w.get("utilization") is None:
            continue
        resets = w.get("resets_at")
        out[label] = (w["utilization"],
                      datetime.fromisoformat(resets).timestamp() if resets else None)
    return out


def codex_limits():
    """~/.codex/auth.json의 토큰으로 ChatGPT 쪽 codex 사용량을 받아온다."""
    tokens = json.loads((Path.home() / ".codex" / "auth.json").read_text()).get("tokens") or {}
    tok = tokens.get("access_token")
    if not tok:
        raise RuntimeError("codex 토큰 없음")
    headers = {"Authorization": f"Bearer {tok}", "Accept": "application/json",
               "User-Agent": "agent-team-usage"}
    if tokens.get("account_id"):
        headers["chatgpt-account-id"] = tokens["account_id"]
    d = http_json("https://chatgpt.com/backend-api/codex/usage", headers)
    rl = d.get("rate_limit") or {}
    out = {"_plan": d.get("plan_type") or "?"}
    for key in ("primary_window", "secondary_window"):
        w = rl.get(key)
        if not w:
            continue
        secs = w.get("limit_window_seconds") or 0
        label = f"{secs // 86400}일" if secs >= 86400 else f"{secs // 3600}시간"
        out[label] = (w.get("used_percent", 0), w.get("reset_at"))
    return out


def live_limits():
    """{cli: {창이름: (사용률%, 리셋 epoch)}} - 실패한 CLI는 사유 문자열.

    캐시에는 성공한 결과만 남긴다. 실패까지 캐시하면 일시적인 네트워크 오류 하나가
    TTL 동안 화면에 박제된다 - 실패한 CLI는 다음 갱신(30초 뒤)에 다시 시도한다.
    """
    data, at = {}, 0
    try:
        cached = json.loads(CACHE.read_text())
        if time.time() - cached.get("_at", 0) < CACHE_TTL:
            data, at = dict(cached.get("data") or {}), cached.get("_at", 0)
    except (OSError, ValueError):
        pass

    fresh = False
    for cli, fn in (("claude", claude_limits), ("codex", codex_limits)):
        if cli in data:
            continue
        try:
            data[cli] = fn()
            fresh = True
        except Exception as e:  # 토큰 만료/네트워크 등 - 한도만 포기하고 나머지는 보여준다
            data[cli] = f"조회 실패 ({type(e).__name__})"

    if fresh:
        at = time.time()
        ok = {k: v for k, v in data.items() if not isinstance(v, str)}
        try:
            CACHE.write_text(json.dumps({"_at": at, "data": ok}))
        except OSError:
            pass
    return data, at or time.time()


def human(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def width(s):
    """한글/한자는 터미널에서 두 칸을 차지한다 - str.ljust는 글자 수만 세서 열이 어긋난다."""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def pad(s, w, right=False):
    fill = " " * max(0, w - width(s))
    return fill + s if right else s + fill


def clip(s, w):
    while width(s) > w:
        s = s[:-1]
    return s


def until(ts):
    left = int(ts - time.time())
    if left <= 0:
        return "곧"
    d, rem = divmod(left, 86400)
    h, m = divmod(rem // 60, 60)
    return f"{d}d {h}h 뒤" if d else (f"{h}h {m}m 뒤" if h else f"{m}m 뒤")


def limit_line(rl):
    parts = []
    for key in ("primary", "secondary"):
        win = rl.get(key)
        if not win:
            continue
        minutes = win.get("window_minutes") or 0
        label = f"{minutes // 1440}일" if minutes >= 1440 else f"{minutes // 60}시간"
        resets = win.get("resets_at")
        tail = f", 리셋 {until(resets)}" if resets else ""
        parts.append(f"{label} {win.get('used_percent', 0):.0f}%{tail}")
    return " · ".join(parts)


NAME_W, MODEL_W, NUM_W = 14, 34, 9


def main():
    agents = lib.load_agents()
    found = collect()

    print(f"토큰 사용량 — 팀: {TEAM}    (30초마다 갱신, {time.strftime('%H:%M:%S')})")
    header = (pad("에이전트", NAME_W) + pad("모델", MODEL_W)
              + "".join(pad(h, NUM_W, right=True) for h in ("입력", "출력", "캐시", "합계"))
              + "  갱신")
    print(header)
    print("-" * width(header))

    for name, (cli, model) in agents.items():
        label = clip(f"{cli}/{model}", MODEL_W - 1)
        row = found.get(name)
        if not row:
            note = "사용량 로그를 남기지 않음" if cli == "antigravity" else "실행 기록 없음"
            print(pad(name, NAME_W) + pad(label, MODEL_W) + note)
            continue
        tot, _, mtime = row
        cache = tot["cache_r"] + tot["cache_w"]
        total = tot["inp"] + tot["out"] + cache
        nums = (tot["inp"], tot["out"], cache, total)
        print(pad(name, NAME_W) + pad(label, MODEL_W)
              + "".join(pad(human(v), NUM_W, right=True) for v in nums)
              + "  " + time.strftime("%H:%M", time.localtime(mtime)))

    limits, fetched = live_limits()
    print(f"\n한도 (실시간, {time.strftime('%H:%M:%S', time.localtime(fetched))} 조회)")
    for cli in ("claude", "codex"):
        info = limits.get(cli)
        if isinstance(info, str):
            print(f"  {pad(cli, 10)}{info}")
            continue
        plan = info.pop("_plan", None)
        name = f"{cli}({plan})" if plan else cli
        windows = " · ".join(
            f"{label} {pct:.0f}%" + (f", 리셋 {until(ts)}" if ts else "")
            for label, (pct, ts) in info.items()) or "창 정보 없음"
        print(f"  {pad(name, 14)}{windows}")
    print(f"  {pad('agy', 14)}한도를 알려주는 CLI 명령도 로컬 기록도 없음")


if __name__ == "__main__":
    main()
