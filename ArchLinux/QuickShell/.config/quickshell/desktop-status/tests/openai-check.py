#!/usr/bin/env python3
"""Offline credit-balance checks; no network requests or real credentials."""

import json
from io import BytesIO
from pathlib import Path
import runpy
import subprocess
from unittest.mock import patch


def check():
    root = Path(__file__).resolve().parents[1]
    module = runpy.run_path(str(root / "scripts/openai_usage.py"))
    normalize = module["normalize_usage"]
    payload = {
        "rate_limit": {"allowed": True, "limit_reached": False, "primary_window": {
            "limit_window_seconds": 18000, "used_percent": 18, "reset_at": 1800005040,
        }},
        "rate_limit_reset_credits": {"available_count": 2},
    }
    for balance, expected in (
        ("1286.4038225000", 1286), ("1286.999999999999999999", 1286),
        (1286, 1286), (1286.4, 1286), ("1", 1), ("0.999", 0), ("0", 0),
        ("9007199254740991", 9007199254740991),
        (None, None), (True, None), ([], None), ({}, None), ("", None),
        ("invalid", None), ("NaN", None), ("Infinity", None), ("-1", None),
        ("9007199254740992", None), ("1e999999999", None),
    ):
        payload["credits"] = {"balance": balance}
        result = normalize(payload, 1800000000000)
        assert result.get("creditBalance") == expected, (balance, result)
        assert result["fiveHour"]["usedPercent"] == 18
        assert result["bankedResets"] == 2, "Reset credits are separate from balance"

    for credits in (None, [], "invalid", {}):
        payload["credits"] = credits
        assert normalize(payload, 1800000000000)["creditBalance"] is None
    del payload["credits"]
    result = normalize(payload, 1800000000000)
    assert result["creditBalance"] is None

    code = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const context = {};
vm.runInNewContext(fs.readFileSync('services/OpenAiUsage.js', 'utf8'), context);
const base = JSON.parse(fs.readFileSync(0, 'utf8'));
for (const [balance, expected] of [
    [undefined, null], [null, null], [0, 0], [1, 1], [1286, 1286],
    [Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER],
    [1286.4, null], ['1286', null], [true, null], [-1, null],
    [Number.MAX_SAFE_INTEGER + 1, null],
]) {
    const result = context.parseStatus(JSON.stringify({...base, creditBalance: balance}));
    assert.ok(result, 'Invalid optional balance must not discard quota');
    assert.equal(result.creditBalance, expected);
    assert.equal(result.fiveHour.usedPercent, 18);
}
for (const encoded of ['1e309', '-1e309']) {
    const text = JSON.stringify({...base, creditBalance: null}).replace('"creditBalance":null', '"creditBalance":' + encoded);
    assert.equal(context.parseStatus(text).creditBalance, null);
}
'''
    subprocess.run(["node", "-e", code], input=json.dumps(result), cwd=root, text=True, check=True)
    for balance, expected in (("0.99999999999999999", 0), ("1286.999999999999999999", 1286),
                              ("1286.4038225000", 1286)):
        encoded = json.dumps({**payload, "credits": {"balance": None}})
        encoded = encoded.replace('"balance": null', '"balance": ' + balance)
        encoded = encoded.replace('"used_percent": 18', '"used_percent": 18.25')
        with patch("urllib.request.build_opener") as opener:
            opener.return_value.open.return_value = BytesIO(encoded.encode())
            result = module["fetch_usage"]({"access": "fixture"})
        assert result["creditBalance"] == expected, (balance, result)
        assert result["fiveHour"]["usedPercent"] == 18.25
        json.dumps(result)
    print("PASS: credit truncation (strings and numeric JSON), invalid/missing balances, optional snapshot validation")


if __name__ == "__main__":
    check()
