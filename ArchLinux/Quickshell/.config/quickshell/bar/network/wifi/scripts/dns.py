#!/usr/bin/env python3
"""Read/write only a Wi-Fi profile's DNS through NetworkManager; never reconnect."""
import ipaddress
import json
import os
import re
import subprocess
import sys
import socket
import struct
import secrets

QUAD9 = {"ipv4": ["9.9.9.9", "149.112.112.112"], "ipv6": ["2620:fe::fe", "2620:fe::9"]}
METHODS = {"auto", "manual", "dhcp"}
DEFAULT_PROVIDERS = [{"id": "quad9", "label": "Quad9", **QUAD9}]


class DnsError(Exception):
    pass


def validate_providers(entries):
    accepted, warnings, ids = [], [], {"automatic", "custom"}
    if not isinstance(entries, list) or len(entries) > 32:
        return [], ["DNS providers must be a list of at most 32 entries"]
    for index, entry in enumerate(entries):
        try:
            if not isinstance(entry, dict): raise ValueError()
            key, label = entry.get("id"), entry.get("label")
            if not isinstance(key, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", key) or key in ids: raise ValueError()
            if not isinstance(label, str) or not label.strip() or len(label) > 32 or any(ord(c) < 32 or ord(c) == 127 for c in label): raise ValueError()
            provider = {"id": key, "label": label.strip()}
            for family, version in (("ipv4", 4), ("ipv6", 6)):
                addresses = entry.get(family, [])
                if not isinstance(addresses, list) or len(addresses) > 8: raise ValueError()
                normalized = []
                for address in addresses:
                    if not isinstance(address, str) or "%" in address: raise ValueError()
                    ip = ipaddress.ip_address(address)
                    if ip.version != version or ip.is_unspecified or ip.is_multicast: raise ValueError()
                    if str(ip) not in normalized: normalized.append(str(ip))
                provider[family] = normalized
            if not provider["ipv4"] and not provider["ipv6"]: raise ValueError()
            accepted.append(provider)
            ids.add(key)
        except ValueError:
            warnings.append(f"DNS provider entry {index + 1} rejected: invalid ID, label, or addresses")
    return accepted, warnings


def test_server(address):
    # A response proves reachability only, not resolver identity or trustworthiness.
    question = b"\x07example\x03com\x00" + struct.pack("!HH", 1, 1)
    transaction = secrets.randbits(16)
    packet = struct.pack("!HHHHHH", transaction, 0x0100, 1, 0, 0, 0) + question
    family = socket.AF_INET6 if ipaddress.ip_address(address).version == 6 else socket.AF_INET
    try:
        with socket.socket(family, socket.SOCK_DGRAM) as connection:
            connection.settimeout(2)
            connection.connect((address, 53))
            connection.send(packet)
            reply = connection.recv(4096)
        if (len(reply) < 12 + len(question) or struct.unpack("!H", reply[:2])[0] != transaction
                or not reply[2] & 0x80 or reply[2] & 0x78 or reply[4:6] != b"\x00\x01"
                or reply[12:12 + len(question)] != question):
            return {"server": address, "status": "error", "detail": "Invalid DNS response"}
        return {"server": address, "status": "response", "detail": "DNS response, RCODE " + str(reply[3] & 15)}
    except socket.timeout:
        return {"server": address, "status": "timeout", "detail": "No response within 2 seconds"}
    except OSError:
        return {"server": address, "status": "error", "detail": "Network/socket error"}


def nmcli(*args):
    try:
        result = subprocess.run(["nmcli", "--wait", "8", *args], capture_output=True, text=True,
                                timeout=10, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.TimeoutExpired):
        raise DnsError("NetworkManager DNS operation unavailable or timed out") from None
    if result.returncode:
        raise DnsError("NetworkManager rejected DNS operation; check profile permissions and authorization")
    return result.stdout


def read_profile(uuid, providers=None):
    providers = DEFAULT_PROVIDERS if providers is None else providers
    if not isinstance(uuid, str) or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", uuid):
        raise DnsError("Invalid connection UUID")
    fields = "connection.type,ipv4.method,ipv4.ignore-auto-dns,ipv4.dns,ipv6.method,ipv6.ignore-auto-dns,ipv6.dns"
    values = nmcli("--escape", "no", "--get-values", fields, "connection", "show", "uuid", uuid).splitlines()
    if len(values) != 7 or values[0] != "802-11-wireless":
        raise DnsError("DNS selection requires a readable Wi-Fi profile")
    families = {}
    states = []
    for family, offset in (("ipv4", 1), ("ipv6", 4)):
        method, ignore, servers = values[offset:offset + 3]
        if ignore not in ("yes", "no"):
            raise DnsError("Invalid NetworkManager DNS response")
        try:
            addresses = {str(ipaddress.ip_address(item.strip())) for item in servers.split(",") if item.strip()}
        except ValueError:
            # Preserve unfamiliar NetworkManager DNS formats as Custom, but allow
            # an explicit replacement (including mandatory home Default).
            addresses = {servers}
        families[family] = method
        if method in METHODS:
            states.append((family, ignore, addresses))
    policy = "custom"
    if states and all(ignore == "no" and not addresses for _, ignore, addresses in states):
        policy = "automatic"
    elif states:
        for provider in providers:
            if all(ignore == "yes" and addresses == set(provider[family]) for family, ignore, addresses in states):
                policy = provider["id"]
                break
    return {"uuid": uuid, "policy": policy, "methods": families}


def active_device(uuid):
    for line in nmcli("--terse", "--escape", "no", "--fields", "UUID,DEVICE", "connection", "show", "--active").splitlines():
        key, _, device = line.partition(":")
        if key == uuid and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}", device):
            return device
    return ""


def save_profile(uuid, policy, providers=None, home_ssids=()):
    providers = DEFAULT_PROVIDERS if providers is None else providers
    provider = next((entry for entry in providers if entry["id"] == policy), None)
    if policy != "automatic" and provider is None:
        raise DnsError("Unsupported DNS choice")
    before = read_profile(uuid, providers)
    is_home = bool(home_ssids) and profile_is_home(uuid, home_ssids)
    if is_home and policy != "automatic":
        raise DnsError("Home network requires router-advertised DNS")
    if provider and any(method in METHODS and not provider[family] for family, method in before["methods"].items()):
        raise DnsError("Provider needs addresses for each enabled IP family")
    args = []
    for family, method in before["methods"].items():
        if method in METHODS:
            args += [family + ".ignore-auto-dns", "yes" if provider else "no",
                     family + ".dns", ",".join(provider[family]) if provider else ""]
    if not args:
        raise DnsError("No DNS-capable IP family on this profile")
    nmcli("connection", "modify", "uuid", uuid, *args)
    # Multiple providers can share endpoints; verify the selected one directly.
    saved = read_profile(uuid, [provider] if provider else [])
    if saved["policy"] != policy:
        raise DnsError("DNS readback did not match selection; reload profile settings")
    saved["application"] = "next-connection"
    saved["home"] = is_home
    try:
        device = active_device(uuid)
        if device and active_device(uuid) == device:
            nmcli("device", "reapply", device)
            saved["application"] = "applied"
    except DnsError:
        saved["application"] = "saved-not-applied"
    return saved


def profile_is_home(uuid, home_ssids):
    return nmcli("--escape", "no", "--get-values", "802-11-wireless.ssid", "connection", "show", "uuid", uuid).rstrip("\n") in home_ssids


def main():
    try:
        # Config is passed as one argv item, never interpolated into shell commands.
        args = sys.argv[1:]
        config = json.loads(args.pop()) if args and args[-1].startswith("{") else {}
        providers, warnings = validate_providers(config.get("providers", DEFAULT_PROVIDERS))
        homes = config.get("homeSsids", [])
        if not isinstance(homes, list) or not all(isinstance(item, str) and len(item) <= 32 for item in homes):
            raise DnsError("Invalid home network configuration")
        if args == ["configure"]:
            result = {"providers": providers, "warnings": warnings}
        elif len(args) == 2 and args[0] == "test":
            provider = next((entry for entry in providers if entry["id"] == args[1]), None)
            if provider is None: raise DnsError("Unsupported DNS provider")
            result = {"provider": provider["id"], "results": [test_server(address) for family in ("ipv4", "ipv6") for address in provider[family]]}
        elif len(args) == 2 and args[0] == "read":
            result = read_profile(args[1], providers)
            if homes and profile_is_home(args[1], homes):
                if result["policy"] != "automatic": result = save_profile(args[1], "automatic", providers, homes)
                result["home"] = True
        elif len(args) == 3 and args[0] == "save":
            result = save_profile(args[1], args[2], providers, homes)
        else:
            raise DnsError("Invalid DNS request")
        print(json.dumps(result))
        return 0
    except (DnsError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
