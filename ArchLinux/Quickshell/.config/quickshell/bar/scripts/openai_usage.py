#!/usr/bin/env python3
"""Read Codex subscription quotas using existing OpenCode OAuth, without refreshing it."""

import json
import math
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


class QuotaError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def normalize_usage(payload, fetched_at):
    limit = payload.get("rate_limit") if isinstance(payload, dict) else None
    if not isinstance(limit, dict) or not isinstance(limit.get("allowed"), bool) or not isinstance(limit.get("limit_reached"), bool):
        raise QuotaError("Unexpected OpenAI quota response")
    windows = {}
    for key in ("primary_window", "secondary_window"):
        window = limit.get(key)
        if window is None:
            continue
        if not isinstance(window, dict):
            raise QuotaError("Unexpected OpenAI quota window")
        duration = window.get("limit_window_seconds")
        if duration not in (18000, 604800):
            continue
        used = window.get("used_percent")
        reset = window.get("reset_at")
        if type(used) not in (int, float) or not math.isfinite(used) or used < 0:
            raise QuotaError("Invalid OpenAI usage percentage")
        if reset is not None and (type(reset) is not int or reset < 0):
            raise QuotaError("Invalid OpenAI reset time")
        windows[duration] = {"usedPercent": used, "resetAt": reset * 1000 if reset is not None else None}
    if not windows:
        raise QuotaError("Five-hour and weekly quotas unavailable")
    return {
        "plan": payload.get("plan_type") if isinstance(payload.get("plan_type"), str) else "unknown",
        "allowed": limit["allowed"],
        "limitReached": limit["limit_reached"],
        "fiveHour": windows.get(18000),
        "weekly": windows.get(604800),
        "fetchedAt": fetched_at,
    }


def read_auth():
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    database = data_home / "opencode/opencode.db"
    auth = None
    try:
        connection = sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True, timeout=1)
        try:
            rows = connection.execute(
                "SELECT value, active FROM credential WHERE integration_id = 'openai' "
                "AND (active = 1 OR active IS NULL) ORDER BY active = 1 DESC LIMIT 2"
            ).fetchall()
        finally:
            connection.close()
        if rows:
            if len(rows) > 1 and rows[0][1] == rows[1][1]:
                raise QuotaError("Multiple OpenCode OpenAI credentials; select one in OpenCode")
            candidate = json.loads(rows[0][0])
            if isinstance(candidate, dict) and candidate.get("type") == "oauth" and isinstance(candidate.get("access"), str) and candidate["access"]:
                auth = candidate
    except (sqlite3.Error, OSError, ValueError):
        # v1, missing schema, or unreadable v2 store: try the legacy credential file.
        pass
    if auth is None:
        auth = read_legacy_auth(data_home)
    expiry = auth.get("expires")
    if type(expiry) in (int, float) and expiry <= time.time() * 1000:
        raise QuotaError("OpenCode login expired; refresh it in OpenCode")
    metadata = auth.get("metadata")
    account_id = metadata.get("accountID") if isinstance(metadata, dict) else None
    return {"access": auth["access"], "accountId": account_id or auth.get("accountId")}


def read_legacy_auth(data_home):
    try:
        data = json.loads((data_home / "opencode/auth.json").read_text())
    except FileNotFoundError:
        raise QuotaError("OpenCode credentials not found") from None
    except (OSError, ValueError):
        raise QuotaError("Cannot read OpenCode credentials") from None
    auth = data.get("openai") if isinstance(data, dict) else None
    if not isinstance(auth, dict) or auth.get("type") != "oauth" or not isinstance(auth.get("access"), str) or not auth["access"]:
        raise QuotaError("OpenCode ChatGPT OAuth login required")
    return auth


def fetch_usage(auth):
    headers = {
        "Authorization": "Bearer " + auth["access"],
        "Accept": "application/json",
        "User-Agent": "quickshell-openai-usage/0.1",
    }
    if isinstance(auth.get("accountId"), str) and auth["accountId"]:
        headers["ChatGPT-Account-Id"] = auth["accountId"]
    request = urllib.request.Request("https://chatgpt.com/backend-api/wham/usage", headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=10) as response:
            raw = response.read(131073)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise QuotaError(f"OpenCode login rejected (HTTP {error.code})") from None
        raise QuotaError(f"Quota request failed (HTTP {error.code})") from None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        raise QuotaError("Cannot reach OpenAI quota service") from None
    if len(raw) > 131072:
        raise QuotaError("Unexpectedly large OpenAI quota response")
    try:
        payload = json.loads(raw)
    except (ValueError, UnicodeError):
        raise QuotaError("Invalid OpenAI quota response") from None
    return normalize_usage(payload, int(time.time() * 1000))


def main():
    try:
        result = fetch_usage(read_auth())
    except QuotaError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
