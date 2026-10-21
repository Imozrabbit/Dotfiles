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
import ssl
import time
from contextlib import ExitStack

QUAD9 = {"ipv4": ["9.9.9.9", "149.112.112.112"], "ipv6": ["2620:fe::fe", "2620:fe::9"]}
METHODS = {"auto", "manual", "dhcp"}
DEFAULT_PROVIDERS = [{"id": "quad9", "label": "Quad9", **QUAD9}]


class DnsError(Exception):
    pass


def normalize_server(address):
    if not isinstance(address, str) or "%" in address:
        raise ValueError("Invalid DNS address")
    host, separator, name = address.partition("#")
    ip = ipaddress.ip_address(host)
    if ip.is_unspecified or ip.is_multicast:
        raise ValueError("Invalid DNS address")
    if separator and (not name or len(name) > 253 or not all(
            re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?", label)
            for label in name.split("."))):
        raise ValueError("Invalid TLS hostname")
    return str(ip) + ("#" + name.lower() if separator else "")


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
            tls = entry.get("tls", False)
            if not isinstance(tls, bool): raise ValueError()
            if tls: provider["tls"] = True
            for family, version in (("ipv4", 4), ("ipv6", 6)):
                addresses = entry.get(family, [])
                if not isinstance(addresses, list) or len(addresses) > 8: raise ValueError()
                normalized = []
                for address in addresses:
                    server = normalize_server(address)
                    if ipaddress.ip_address(server.split("#")[0]).version != version or ("#" in server) != tls: raise ValueError()
                    if server not in normalized: normalized.append(server)
                provider[family] = normalized
            if not provider["ipv4"] and not provider["ipv6"]: raise ValueError()
            accepted.append(provider)
            ids.add(key)
        except ValueError:
            warnings.append(f"DNS provider entry {index + 1} rejected: invalid ID, label, addresses, or TLS settings")
    return accepted, warnings


def recv_exact(connection, size, deadline):
    data = bytearray()
    while len(data) < size:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError()
        connection.settimeout(remaining)
        chunk = connection.recv(size - len(data))
        if not chunk:
            raise OSError("Incomplete DNS-over-TLS frame")
        data.extend(chunk)
    return bytes(data)


def test_server(address, tls=False):
    # A response proves reachability only, not resolver identity or trustworthiness.
    question = b"\x07example\x03com\x00" + struct.pack("!HH", 1, 1)
    transaction = secrets.randbits(16)
    packet = struct.pack("!HHHHHH", transaction, 0x0100, 1, 0, 0, 0) + question
    host, _, hostname = normalize_server(address).partition("#")
    if tls and not hostname:
        raise DnsError("DNS-over-TLS requires a certificate hostname")
    family = socket.AF_INET6 if ipaddress.ip_address(host).version == 6 else socket.AF_INET
    try:
        deadline = time.monotonic() + 2
        with ExitStack() as sockets:
            connection = sockets.enter_context(socket.socket(family, socket.SOCK_STREAM if tls else socket.SOCK_DGRAM))
            connection.settimeout(2)
            connection.connect((host, 853 if tls else 53))
            if tls:
                context = ssl.create_default_context()
                remaining = deadline - time.monotonic()
                if remaining <= 0: raise TimeoutError()
                connection.settimeout(remaining)
                connection = sockets.enter_context(context.wrap_socket(connection, server_hostname=hostname))
                remaining = deadline - time.monotonic()
                if remaining <= 0: raise TimeoutError()
                connection.settimeout(remaining)
                connection.sendall(struct.pack("!H", len(packet)) + packet)
                size = struct.unpack("!H", recv_exact(connection, 2, deadline))[0]
                reply = recv_exact(connection, size, deadline)
            else:
                connection.send(packet)
                reply = connection.recv(4096)
        if (len(reply) < 12 + len(question) or struct.unpack("!H", reply[:2])[0] != transaction
                or not reply[2] & 0x80 or reply[2] & 0x78 or reply[4:6] != b"\x00\x01"
                or reply[12:12 + len(question)] != question):
            return {"server": address, "status": "error", "detail": "Invalid DNS response"}
        return {"server": address, "status": "response", "detail": ("TLS verified; " if tls else "") + "DNS response, RCODE " + str(reply[3] & 15)}
    except socket.timeout:
        return {"server": address, "status": "timeout", "detail": "No response within 2 seconds"}
    except ssl.SSLCertVerificationError:
        return {"server": address, "status": "error", "detail": "TLS certificate verification failed"}
    except OSError:
        return {"server": address, "status": "error", "detail": "Network/TLS error" if tls else "Network/socket error"}


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
    fields = "connection.type,ipv4.method,ipv4.ignore-auto-dns,ipv4.dns,ipv6.method,ipv6.ignore-auto-dns,ipv6.dns,connection.dns-over-tls"
    values = nmcli("--escape", "no", "--get-values", fields, "connection", "show", "uuid", uuid).splitlines()
    if len(values) != 8 or values[0] != "802-11-wireless":
        raise DnsError("DNS selection requires a readable Wi-Fi profile")
    mode = values[7]
    if mode not in ("-1", "0", "1", "2"):
        raise DnsError("Invalid NetworkManager DNS-over-TLS response")
    families = {}
    states = []
    for family, offset in (("ipv4", 1), ("ipv6", 4)):
        method, ignore, servers = values[offset:offset + 3]
        if ignore not in ("yes", "no"):
            raise DnsError("Invalid NetworkManager DNS response")
        try:
            addresses = {normalize_server(item.strip()) for item in servers.split(",") if item.strip()}
        except ValueError:
            # Preserve unfamiliar NetworkManager DNS formats as Custom, but allow
            # an explicit replacement (including mandatory home Default).
            addresses = {servers}
        families[family] = method
        if method in METHODS:
            states.append((family, ignore, addresses))
    policy = "custom"
    if mode in ("-1", "0") and states and all(ignore == "no" and not addresses for _, ignore, addresses in states):
        policy = "automatic"
    elif states:
        for provider in providers:
            matches_mode = mode == "2" if provider.get("tls") else mode in ("-1", "0")
            if matches_mode and all(ignore == "yes" and addresses == set(provider[family]) for family, ignore, addresses in states):
                policy = provider["id"]
                break
    return {"uuid": uuid, "policy": policy, "methods": families, "tlsMode": mode}


def active_device(uuid):
    for line in nmcli("--terse", "--escape", "no", "--fields", "UUID,DEVICE", "connection", "show", "--active").splitlines():
        key, _, device = line.partition(":")
        if key == uuid and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}", device):
            return device
    return ""


def require_resolved():
    # NetworkManager ignores dns-over-tls with unsupported DNS plugins.
    try:
        result = subprocess.run(["busctl", "--system", "get-property", "org.freedesktop.NetworkManager",
                                 "/org/freedesktop/NetworkManager/DnsManager",
                                 "org.freedesktop.NetworkManager.DnsManager", "Mode"],
                                capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        raise DnsError("Cannot verify systemd-resolved DNS backend; DoT was not saved") from None
    if result.returncode or result.stdout.strip() != 's "systemd-resolved"':
        raise DnsError("Strict DoT requires NetworkManager's systemd-resolved DNS backend")


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
    tls = bool(provider and provider.get("tls"))
    if tls:
        require_resolved()
    args = []
    for family, method in before["methods"].items():
        if method in METHODS:
            args += [family + ".ignore-auto-dns", "yes" if provider else "no",
                     family + ".dns", ",".join(provider[family]) if provider else ""]
    if not args:
        raise DnsError("No DNS-capable IP family on this profile")
    nmcli("connection", "modify", "uuid", uuid, *args, "connection.dns-over-tls", "yes" if tls else "no")
    # Multiple providers can share endpoints; verify the selected one directly.
    saved = read_profile(uuid, [provider] if provider else [])
    if saved["policy"] != policy or saved["tlsMode"] != ("2" if tls else "0"):
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
            result = {"provider": provider["id"], "results": [test_server(address, tls=provider.get("tls", False)) for family in ("ipv4", "ipv6") for address in provider[family]]}
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
