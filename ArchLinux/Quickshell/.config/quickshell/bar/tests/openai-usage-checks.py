import importlib.util
import json
import sqlite3
import sys
import tempfile
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
with patch.dict(usage.os.environ, {"XDG_DATA_HOME": "/nonexistent-quota-test"}), patch.object(usage.Path, "read_text", return_value=json.dumps({"openai": {
    "type": "oauth", "access": "test-secret", "refresh": "unused-refresh", "accountId": "test-account", "expires": 2000000000000
}})), patch.object(usage.time, "time", return_value=1900000000):
    assert "refresh" not in usage.read_auth()
with patch.dict(usage.os.environ, {"XDG_DATA_HOME": "/nonexistent-quota-test"}), patch.object(usage.Path, "read_text", return_value=json.dumps({"openai": {
    "type": "oauth", "access": "test-secret", "expires": 1800000000000
}})), patch.object(usage.time, "time", return_value=1900000000):
    try:
        usage.read_auth()
        raise AssertionError("expired login accepted")
    except usage.QuotaError:
        pass
with tempfile.TemporaryDirectory(dir=path.parent.parent / "tests") as directory:
    home = Path(directory)
    store = home / "opencode"
    store.mkdir()
    legacy = {"openai": {"type": "oauth", "access": "legacy-test", "expires": 2000000000000}}
    (store / "auth.json").write_text(json.dumps(legacy))
    database = store / "opencode.db"
    with patch.dict(usage.os.environ, {"XDG_DATA_HOME": str(home)}), patch.object(usage.time, "time", return_value=1900000000):
        assert usage.read_auth()["access"] == "legacy-test"
        assert not database.exists(), "reader must not create database"
        with sqlite3.connect(database) as db:
            db.execute("CREATE TABLE credential (integration_id TEXT, active INTEGER, value TEXT)")
            credential = {"type": "oauth", "access": "database-test", "expires": 2000000000000,
                          "refresh": "unused-test", "metadata": {"accountID": "database-account"}}
            db.execute("INSERT INTO credential VALUES ('openai', NULL, ?)", (json.dumps(credential),))
        original = database.read_bytes()
        assert usage.read_auth() == {"access": "database-test", "accountId": "database-account"}
        assert database.read_bytes() == original, "reader must not modify database"
        with sqlite3.connect(database) as db:
            credential["access"] = "active-test"
            db.execute("INSERT INTO credential VALUES ('openai', 1, ?)", (json.dumps(credential),))
        assert usage.read_auth()["access"] == "active-test"
        with sqlite3.connect(database) as db:
            credential["expires"] = 1800000000000
            db.execute("UPDATE credential SET value = ? WHERE active = 1", (json.dumps(credential),))
        try:
            usage.read_auth()
            raise AssertionError("expired database credential must not fall back to stale JSON")
        except usage.QuotaError as error:
            assert "expired" in str(error)
        with sqlite3.connect(database) as db:
            db.execute("DELETE FROM credential")
        assert usage.read_auth()["access"] == "legacy-test"
        with sqlite3.connect(database) as db:
            db.execute("INSERT INTO credential VALUES ('openai', 0, ?)", (json.dumps(credential),))
        assert usage.read_auth()["access"] == "legacy-test", "inactive credentials must not be selected"
        with sqlite3.connect(database) as db:
            credential["expires"] = 2000000000000
            db.execute("INSERT INTO credential VALUES ('openai', NULL, ?)", (json.dumps(credential),))
            db.execute("INSERT INTO credential VALUES ('openai', NULL, ?)", (json.dumps(credential),))
        try:
            usage.read_auth()
            raise AssertionError("ambiguous credentials accepted")
        except usage.QuotaError as error:
            assert "Multiple" in str(error)
        with sqlite3.connect(database) as db:
            db.execute("DROP TABLE credential")
        assert usage.read_auth()["access"] == "legacy-test", "v1 database schema must allow JSON fallback"
print("OpenAI quota checks passed; only synthetic credentials used, no network requests made")
