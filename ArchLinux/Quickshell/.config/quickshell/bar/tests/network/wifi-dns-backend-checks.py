import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location("wifi_dns", Path(__file__).parents[2] / "network/wifi/scripts/dns.py")
assert spec.origin and Path(spec.origin).exists(), "DNS backend must exist"
dns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dns)
uuid = "11111111-1111-1111-1111-111111111111"
providers, warnings = dns.validate_providers([
    {"id":"quad9","label":"Quad9",**dns.QUAD9},
    {"id":"bad","label":"Bad","ipv4":["not-an-ip"],"ipv6":[]},
    {"id":"cloudflare","label":"Cloudflare","ipv4":["1.1.1.1"],"ipv6":[]}
])
assert [p["id"] for p in providers] == ["quad9", "cloudflare"] and warnings
assert dns.validate_providers([{"id":"automatic","label":"Default","ipv4":["1.1.1.1"]}])[0] == []
with patch.object(dns.secrets,"randbits",return_value=123), patch.object(dns.socket,"socket") as sock:
    connection=MagicMock()
    sock.return_value.__enter__.return_value=connection
    connection.recv.return_value=dns.struct.pack("!HHHHHH",123,0x8180,1,0,0,0)
    assert dns.test_server("9.9.9.9")["status"]=="error", "Header without echoed question is not a valid DNS response"
    question=b"\x07example\x03com\x00"+dns.struct.pack("!HH",1,1)
    connection.recv.return_value+=question
    assert dns.test_server("9.9.9.9")["status"]=="response"
default = "802-11-wireless\nauto\nno\n\nauto\nno\n\n0\n"
quad9 = "802-11-wireless\nauto\nyes\n9.9.9.9,149.112.112.112\nauto\nyes\n2620:fe::fe,2620:fe::9\n0\n"
with patch.object(dns, "nmcli", return_value=default):
    assert dns.read_profile(uuid)["policy"] == "automatic"
with patch.object(dns, "nmcli", return_value=quad9):
    assert dns.read_profile(uuid)["policy"] == "quad9"
with patch.object(dns, "nmcli", return_value=quad9.replace("9.9.9.9,149.112.112.112", "1.1.1.1")):
    assert dns.read_profile(uuid)["policy"] == "custom"
with patch.object(dns, "nmcli", return_value=quad9.replace("9.9.9.9,149.112.112.112", "dns+tls://9.9.9.9")):
    assert dns.read_profile(uuid)["policy"] == "custom", "Unrecognized custom DNS must not prevent Default/home reset"
for bad in ["--help", "a; touch /tmp/no", "", "bad"]:
    try: dns.read_profile(bad)
    except dns.DnsError: pass
    else: raise AssertionError("Invalid UUID accepted")
calls = []
def fake(*args):
    calls.append(args)
    if "modify" in args: return ""
    if "--active" in args: return ""
    return quad9 if any("modify" in call for call in calls) else default
with patch.object(dns, "nmcli", side_effect=fake):
    result = dns.save_profile(uuid, "quad9")
    assert result["policy"] == "quad9" and result["application"] == "next-connection"
assert sum("modify" in call for call in calls) == 1
assert not any("up" in call or "down" in call for call in calls)
assert all("--show-secrets" not in call for call in calls)
calls = []
alias = {"id":"alias", "label":"Same servers", **dns.QUAD9}
with patch.object(dns, "nmcli", side_effect=fake):
    assert dns.save_profile(uuid, "alias", dns.DEFAULT_PROVIDERS + [alias])["policy"] == "alias", "Equivalent provider must not fail after writing"
for policy, initial, final in (("automatic", quad9, default), ("quad9", default, quad9)):
    calls = []
    def connected(*args):
        calls.append(args)
        if "modify" in args or "reapply" in args:
            return ""
        if "--active" in args:
            return uuid + ":wlan0\n"
        return final if any("modify" in call for call in calls) else initial
    with patch.object(dns, "nmcli", side_effect=connected):
        result = dns.save_profile(uuid, policy)
        assert result["application"] == "applied"
    modify = next(call for call in calls if "modify" in call)
    assert modify[modify.index("ipv4.ignore-auto-dns") + 1] == ("yes" if policy == "quad9" else "no")
    assert modify[modify.index("ipv4.dns") + 1] == ("9.9.9.9,149.112.112.112" if policy == "quad9" else "")
    assert any("reapply" in call for call in calls)
    calls = []
    def failed_reapply(*args):
        if "reapply" in args: raise dns.DnsError("Denied")
        return connected(*args)
    with patch.object(dns, "nmcli", side_effect=failed_reapply):
        assert dns.save_profile(uuid, policy)["application"] == "saved-not-applied"
with patch.object(dns, "nmcli", side_effect=dns.DnsError("Denied")):
    try: dns.save_profile(uuid, "quad9")
    except dns.DnsError: pass
    else: raise AssertionError("Permission failure must not report success")
calls = []
def home(*args):
    calls.append(args)
    if "802-11-wireless.ssid" in args: return "Home\n"
    if "modify" in args: return ""
    if "--active" in args: return ""
    return default if any("modify" in call for call in calls) else quad9
with patch.object(dns, "nmcli", side_effect=home):
    try: dns.save_profile(uuid, "quad9", home_ssids=["Home"])
    except dns.DnsError: pass
    else: raise AssertionError("Home must reject non-default DNS")
assert not any("modify" in call for call in calls)
with patch.object(dns, "nmcli", side_effect=home), patch.object(dns.sys,"argv",["dns.py","read",uuid,json.dumps({"homeSsids":["Home"]})]):
    output = io.StringIO()
    with redirect_stdout(output): assert dns.main() == 0
    assert json.loads(output.getvalue())["home"] is True
assert any("modify" in call for call in calls), "Home manual DNS must reset to automatic"
with patch.object(dns,"test_server",side_effect=lambda address, **kwargs:{"server":address,"status":"timeout"}) as probe, \
     patch.object(dns,"nmcli",side_effect=AssertionError("DNS tests cannot mutate profiles")), \
     patch.object(dns.sys,"argv",["dns.py","test","quad9","{}"]):
    output = io.StringIO()
    with redirect_stdout(output): assert dns.main() == 0
    assert len(json.loads(output.getvalue())["results"]) == 4
    assert probe.call_count == 4, "Every server needs its own result"
print("DNS backend checks passed (synthetic profiles only)")
