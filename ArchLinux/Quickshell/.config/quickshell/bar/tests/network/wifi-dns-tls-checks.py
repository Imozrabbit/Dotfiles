"""DoT checks: synthetic profiles/sockets only; no live DNS or NetworkManager writes."""
import importlib.util
import io
import json
import ssl
import subprocess
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("wifi_dns", Path(__file__).parents[2] / "network/wifi/scripts/dns.py")
dns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dns)
uuid = "11111111-1111-1111-1111-111111111111"
provider = {"id": "nextdns", "label": "NextDNS", "tls": True,
            "ipv4": ["45.90.28.0#abcdef.dns.nextdns.io"],
            "ipv6": ["2a07:a8c0::#abcdef.dns.nextdns.io"]}
providers, warnings = dns.validate_providers([provider])
assert not warnings and providers == [provider], "Accept profile-aware strict DoT provider"
for changes in ({"tls": "yes"}, {"tls": False}, {"ipv4": ["45.90.28.0"]},
                {"ipv4": ["45.90.28.0#"]}, {"ipv4": ["45.90.28.0#-bad.example"]},
                {"ipv4": ["45.90.28.0#bad.example:853"]},
                {"ipv6": ["fe80::1%wlan0#dns.example"]}):
    assert not dns.validate_providers([{**provider, **changes}])[0], changes
upper = {**provider, "ipv4": ["45.90.28.0#ABCDEF.DNS.NEXTDNS.IO"]}
assert dns.validate_providers([upper])[0][0]["ipv4"] == provider["ipv4"]

automatic = "802-11-wireless\nauto\nno\n\nauto\nno\n\n0\n"
encrypted = ("802-11-wireless\nauto\nyes\n" + provider["ipv4"][0]
             + "\nauto\nyes\n" + provider["ipv6"][0] + "\n2\n")
with patch.object(dns, "nmcli", return_value=encrypted):
    assert dns.read_profile(uuid, providers)["policy"] == "nextdns"
for value in (encrypted[:-2] + "1\n", encrypted.replace("abcdef.", "other."),
              automatic[:-2] + "2\n"):
    with patch.object(dns, "nmcli", return_value=value):
        assert dns.read_profile(uuid, providers)["policy"] == "custom", "DoT mode and hostname must match"
with patch.object(dns, "nmcli", return_value=automatic.replace("802-11-wireless", "802-3-ethernet")):
    try: dns.save_profile(uuid, "nextdns", providers)
    except dns.DnsError: pass
    else: raise AssertionError("Ethernet remains outside panel write scope")

for policy, initial, final in (("nextdns", automatic, encrypted), ("automatic", encrypted, automatic)):
    calls = []
    def nmcli(*args):
        calls.append(args)
        if "modify" in args or "--active" in args: return ""
        return final if any("modify" in call for call in calls) else initial
    supported = subprocess.CompletedProcess([], 0, 's "systemd-resolved"\n', "")
    with patch.object(dns, "nmcli", side_effect=nmcli), patch.object(dns.subprocess, "run", return_value=supported):
        assert dns.save_profile(uuid, policy, providers)["policy"] == policy
    modify = next(call for call in calls if "modify" in call)
    assert modify[modify.index("connection.dns-over-tls") + 1] == ("yes" if policy == "nextdns" else "no")
    assert modify[modify.index("ipv4.dns") + 1] == (provider["ipv4"][0] if policy == "nextdns" else "")
    assert not any("up" in call or "down" in call or any("route" in arg for arg in call) for call in calls)

for result in (subprocess.CompletedProcess([], 0, 's "dnsmasq"\n', ""),
               subprocess.CompletedProcess([], 1, "", ""), FileNotFoundError()):
    with patch.object(dns, "nmcli", return_value=automatic) as nm, \
         patch.object(dns.subprocess, "run", **({"side_effect": result} if isinstance(result, Exception) else {"return_value": result})):
        try: dns.save_profile(uuid, "nextdns", providers)
        except dns.DnsError: pass
        else: raise AssertionError("Strict DoT must reject unsupported/unknown DNS backend")
    assert not any("modify" in call.args for call in nm.call_args_list)

question = b"\x07example\x03com\x00" + dns.struct.pack("!HH", 1, 1)
reply = dns.struct.pack("!HHHHHH", 123, 0x8180, 1, 0, 0, 0) + question
with patch.object(dns.secrets, "randbits", return_value=123), \
     patch.object(dns.socket, "socket") as sockets, \
     patch.object(dns.ssl, "create_default_context") as contexts:
    raw = sockets.return_value.__enter__.return_value
    tls = contexts.return_value.wrap_socket.return_value.__enter__.return_value
    wire = dns.struct.pack("!H", len(reply)) + reply
    # Deliberately fragmented stream: TLS is not a datagram transport.
    tls.recv.side_effect = [wire[:1], wire[1:2], wire[2:7], wire[7:]]
    result = dns.test_server(provider["ipv4"][0], tls=True)
    assert result["status"] == "response" and "TLS verified" in result["detail"]
    raw.connect.assert_called_with(("45.90.28.0", 853))
    contexts.return_value.wrap_socket.assert_called_once_with(raw, server_hostname="abcdef.dns.nextdns.io")
    tls.sendall.assert_called_once()
    assert tls.sendall.call_args.args[0][2:] == dns.struct.pack("!HHHHHH", 123, 0x0100, 1, 0, 0, 0) + question
    contexts.return_value.wrap_socket.side_effect = ssl.SSLCertVerificationError("wrong hostname")
    assert dns.test_server(provider["ipv4"][0], tls=True)["status"] == "error"
    assert sockets.call_count == 2, "Failed TLS must not fall back to UDP"
    contexts.return_value.wrap_socket.side_effect = None
    tls.recv.side_effect = [b""]
    assert dns.test_server(provider["ipv4"][0], tls=True)["status"] == "error", "Truncated TLS frame must fail"
    tls.recv.side_effect = TimeoutError()
    assert dns.test_server(provider["ipv6"][0], tls=True)["status"] == "timeout"

with patch.object(dns, "test_server", return_value={"status": "response"}) as probe, \
     patch.object(dns, "nmcli", side_effect=AssertionError("Tests cannot write settings")), \
     patch.object(dns.sys, "argv", ["dns.py", "test", "nextdns", json.dumps({"providers": providers})]):
    with redirect_stdout(io.StringIO()): assert dns.main() == 0
    assert probe.call_count == 2
    assert all(call.kwargs == {"tls": True} for call in probe.call_args_list)
print("Wi-Fi strict DoT validation, profile writes/readback and TLS transport checks passed")
