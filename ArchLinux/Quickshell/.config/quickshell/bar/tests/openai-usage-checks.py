import importlib.util
import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.dont_write_bytecode = True
path = Path(__file__).resolve().parents[1] / "scripts" / "openai_usage.py"
spec = importlib.util.spec_from_file_location("openai_usage", path)
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)

payload = {
    "plan_type": "plus", "email": "private@example.invalid", "account_id": "private",
    "rate_limit": {
        "allowed": True, "limit_reached": False,
        "primary_window": {"used_percent": 22, "limit_window_seconds": 18000, "reset_at": 2000000000},
        "secondary_window": {"used_percent": 3, "limit_window_seconds": 604800, "reset_at": 2000500000}
    }
}
result = usage.normalize_usage(payload, 1900000000000)
assert result["fiveHour"]["usedPercent"] == 22
assert result["fiveHour"]["resetAt"] == 2000000000000
assert result["weekly"]["usedPercent"] == 3
assert "email" not in result and "account_id" not in result

swapped = json.loads(json.dumps(payload))
rate = swapped["rate_limit"]
rate["primary_window"], rate["secondary_window"] = rate["secondary_window"], rate["primary_window"]
assert usage.normalize_usage(swapped, 1900000000000)["fiveHour"]["usedPercent"] == 22
for bad in [{}, {"rate_limit": {"allowed": "yes", "limit_reached": False}}]:
    try:
        usage.normalize_usage(bad, 1900000000000)
        raise AssertionError("invalid response accepted")
    except usage.QuotaError:
        pass

opener = MagicMock()
opener.open.return_value.__enter__.return_value.read.return_value = json.dumps(payload).encode()
with patch.object(usage.urllib.request, "build_opener", return_value=opener):
    usage.fetch_usage({"access": "test-secret", "accountId": "test-account"})
request = opener.open.call_args.args[0]
assert request.full_url == "https://chatgpt.com/backend-api/wham/usage"
assert request.get_method() == "GET"
assert request.get_header("Authorization") == "Bearer test-secret"
assert usage.NoRedirect().redirect_request(None, None, 302, "redirect", {}, "https://other.invalid") is None
with patch.object(usage.Path, "read_text", return_value=json.dumps({"openai": {
    "type": "oauth", "access": "test-secret", "refresh": "unused-refresh", "accountId": "test-account", "expires": 2000000000000
}})), patch.object(usage.time, "time", return_value=1900000000):
    assert "refresh" not in usage.read_auth()
with patch.object(usage.Path, "read_text", return_value=json.dumps({"openai": {
    "type": "oauth", "access": "test-secret", "expires": 1800000000000
}})), patch.object(usage.time, "time", return_value=1900000000):
    try:
        usage.read_auth()
        raise AssertionError("expired login accepted")
    except usage.QuotaError:
        pass
print("OpenAI quota checks passed; no credentials read or network requests made")
