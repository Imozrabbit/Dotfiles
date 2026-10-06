import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const api = {};
runInNewContext(await readFile(new URL("../../network/vpn/VpnDns.js", import.meta.url), "utf8").catch(() => ""), api);
assert.equal(typeof api.vpnState, "function");
assert.equal(api.vpnState([], ["Home"], ["Home"]).mode, "home");
assert.equal(api.vpnState(null, ["Home"], ["Home"]).mode, "unknown");
assert.equal(api.vpnState([], [], ["Home"]).mode, "unprotected");
const local = api.parseConnections("uuid:Proton\\: VPN:wireguard:wg0\nlan:Ethernet:802-3-ethernet:eth0\n");
assert.equal(local[0].name, "Proton: VPN");
assert.equal(api.vpnState(local, ["Home"], ["Home"]).mode, "vpn");
assert.equal(api.vpnState(local, [], []).name, "Proton: VPN");
assert.equal(api.parseConnections("malformed"), null);

const devices = api.parseDevices("GENERAL.DEVICE:eth0\nGENERAL.TYPE:ethernet\nGENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:Ethernet\nIP4.GATEWAY:192.168.1.1\nIP6.GATEWAY:fe80\\:\\:1\n\nGENERAL.DEVICE:wg0\nGENERAL.TYPE:wireguard\nGENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:Proton\\: VPN\nIP4.GATEWAY:\n");
assert.equal(devices.eth0.gateways[0], "192.168.1.1");
const rows = api.parseDns("Global:\nLink 2 (eth0): 192.168.1.1\n");
assert.equal(api.classifyDns(rows, devices, local).kind, "router");
assert.equal(api.classifyDns(api.parseDns("Link 3 (wg0): 10.2.0.1"), devices, local).kind, "vpn");
assert.equal(api.classifyDns(api.parseDns("Link 3 (wg0): 45.90.28.0#example.dns.nextdns.io"), devices, local).kind, "nextdns");
assert.equal(api.classifyDns(api.parseDns("Link 2 (eth0): 2a07:a8c0:0:0:0:0:0:0"), devices, []).kind, "nextdns");
assert.equal(api.classifyDns(api.parseDns("Link 2 (eth0): fe80::1"), devices, []).kind, "router");
assert.equal(api.classifyDns(api.parseDns("Link 2 (eth0): 1.1.1.1"), devices, []).kind, "other");
assert.equal(api.classifyDns(api.parseDns("Link 2 (eth0): 192.168.1.1 1.1.1.1"), devices, []).kind, "mixed");
assert.equal(api.classifyDns(rows, {}, []).kind, "other", "no gateway evidence must not imply router DNS");
assert.equal(api.classifyDns([], devices, local).kind, "unavailable");
assert.equal(api.parseDns("bad output"), null);
assert.equal(api.parseDns("Link 2 (eth0): 999.1.2.3"), null);
assert.equal(api.classifyDns(api.parseDns("Link 2 (eth0): ::ffff:192.0.2.1"), devices, []).kind, "other");
assert.equal(api.parseDns("Link 2 (eth0): ::ffff:999.0.2.1"), null);
const rawIpv6 = api.parseDevices("GENERAL.DEVICE:eth0\nGENERAL.TYPE:ethernet\nGENERAL.STATE:100 (connected)\nIP6.GATEWAY:fe80::1\n");
assert.notEqual(rawIpv6, null, "nmcli emits unescaped IPv6 gateway colons");
assert.equal(rawIpv6.eth0.gateways[0], "fe80:0:0:0:0:0:0:1");
assert.equal(api.parseDns("Global:\nLink 9 (wg0): 45.90.28.0#example.dns.nextdns.io\n        45.90.30.0#example.dns.nextdns.io\n").length, 2, "wrapped resolver lines retain interface");
assert.equal(typeof api.parseDnsStatus, "function");
const tail = `Link 5 (tailscale0)
    Current Scopes: DNS
         Protocols: -DefaultRoute
       DNS Servers: 100.100.100.100 fd7a:115c:a1e0::53
        DNS Domain: example.ts.net ~100.100.in-addr.arpa
                    ~ts.net
     Default Route: no
`;
const homeStatus = `Global
Fallback DNS Servers: 9.9.9.9

${tail}
Link 2 (eth0)
    Current Scopes: DNS LLMNR/IPv4
         Protocols: +DefaultRoute
Current DNS Server: 192.168.1.1
       DNS Servers: 192.168.1.1
        DNS Domain: lan
     Default Route: yes
`;
const homeRows = api.parseDnsStatus(homeStatus);
assert.equal(api.classifyDns(homeRows, devices, []).kind, "router", "split DNS must not contaminate ordinary Internet DNS");
assert.equal(homeRows.length, 1);
const hotspotStatus = `${homeStatus}
Link 9 (wg0)
    Current Scopes: DNS
         Protocols: +DefaultRoute +DNSOverTLS
Current DNS Server: 45.90.28.0#example.dns.nextdns.io
       DNS Servers: 45.90.28.0#example.dns.nextdns.io
                    45.90.30.0#example.dns.nextdns.io
                    2a07:a8c0::#example.dns.nextdns.io
                    2a07:a8c1::#example.dns.nextdns.io
        DNS Domain: ~.
     Default Route: yes
`;
const hotspotRows = api.parseDnsStatus(hotspotStatus);
assert.equal(hotspotRows.length, 4);
assert.equal(api.classifyDns(hotspotRows, devices, local).kind, "nextdns", "root DNS route overrides physical default and split DNS");
assert.equal(api.parseDnsStatus("invalid output"), null);
assert.equal(api.parseDnsStatus("Global\nFallback DNS Servers: 9.9.9.9\n" ).length, 1);
assert.equal(api.parseDnsStatus("Global\nLink 2 (eth0)\n    Current Scopes: none\n       DNS Servers: 192.168.1.1\n     Default Route: yes\n").length, 0);
const mixedStatus = homeStatus + "\nLink 8 (other0)\n    Current Scopes: DNS\n       DNS Servers: 1.1.1.1\n     Default Route: yes\n";
assert.equal(api.classifyDns(api.parseDnsStatus(mixedStatus), devices, []).kind, "mixed", "different ordinary DNS categories still show mixed");
console.log("VPN/DNS classification checks passed");
