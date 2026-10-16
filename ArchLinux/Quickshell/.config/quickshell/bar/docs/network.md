# Wi-Fi, DNS, and VPN

[Back to bar setup and configuration](../README.md)

## Per-network DNS

Click a connected or saved Wi-Fi card to expand **DNS [ Default | Quad9 | … ]**.
Only one card expands at a time; Connect/Disconnect remain separate actions.
Opening a card reads its saved NetworkManager settings. Selecting a segment:

- **Default:** accepts network-advertised DNS for supported IPv4/IPv6 methods.
- **Quad9:** sets Quad9 IPv4/IPv6 addresses and ignores automatically supplied DNS.
- Other configured providers use their specified addresses; choices wrap onto
  additional rows. Default is built-in and cannot be replaced by a provider entry.
- Saves the profile, verifies readback, and attempts live application when connected.
  Disconnected profiles use the choice next time. No deliberate reconnect occurs.

Feedback distinguishes saved/applied, saved for next connection, authorization
failures, and saved-but-not-applied. If live application fails, reconnect when
convenient. NetworkManager may require a running Polkit agent.

Existing custom DNS leaves provider segments unselected and remains unchanged until
you explicitly choose a replacement. Unrecognized server formats are treated as
Custom, not errors; use Advanced Settings to edit them rather than replace them.
Captive portals and private network names may need Default DNS.

### New-network prompt

After this panel successfully creates/connects a new non-home profile, its DNS
selector opens. `dns.preferredProvider` suggests a choice (Quad9 by default);
nothing is automatically applied. **Later** keeps current DNS. Reconnecting
saved profiles and external connections do not trigger this prompt.

### Home exception

Wi-Fi names in `vpn.routerManagedSsids` always use automatic/network-advertised
DNS. Their cards show router-DNS status instead of provider choices; pending or
failed checks say **Router DNS required**, not that the setting is already active.
The backend rejects non-default saves and resets manual DNS when a home profile
is read or an active home connection is detected. NetworkManager events trigger
checks even with the panel closed. This is asynchronous enforcement while the
Wi-Fi module runs, not an OS-wide lock against other tools. Saved inactive home
profiles are corrected when opened or connected. Apply failures remain visible;
reconnect when convenient if live application fails.

This accepts the DNS advertised by the home network; it neither verifies nor
changes the router's upstream DNS.

### Configured providers

Use global `dns.providers` entries with `id`, `label`, `ipv4`, and `ipv6` lists;
see the complete JSON example in [README](../README.md). Omitted configuration
keeps Quad9. An explicit list replaces the defaults; `[]` leaves only Default.
`dns.preferredProvider` falls back to the first accepted provider or Default if
its ID is unavailable. Removing/changing a provider does not rewrite saved DNS;
unmatched saved addresses appear as Custom. Recognition uses address sets, not
stored provider IDs; equivalent definitions resolve to the first matching entry.

Validation happens before entries become selectable: unique lowercase IDs
(letters, digits, `_`, `-`; maximum 32 characters), labels up to 32 characters,
correct IPv4/IPv6 lists, and at least one address. IDs `automatic` and `custom`
are reserved. Limits: 32 providers, eight addresses per family. Malformed,
multicast, unspecified, and zone-qualified addresses are rejected with visible
configuration warnings. Private DNS addresses are allowed. Saving requires
addresses for every DNS-capable IP family enabled on that profile.

**Test provider** queries every configured server individually using a standard
UDP DNS query for `example.com` on port 53, with a two-second timeout per server.
Results distinguish response (with DNS RCODE), timeout, and socket/response
error. Testing never modifies profiles or system DNS; it is manual, not a
background probe or visibility gate. A response does not establish resolver
identity, trustworthiness, privacy, or future availability; networks may block
DNS or lack IPv6 connectivity.

### Policy versus observed DNS

The selector shows saved policy; the network tooltip independently reports
resolver routing. Selecting Quad9 does not enable encrypted DNS or guarantee
every query uses Quad9. VPN/Tailscale profiles and routes are not modified.
Domain-specific split DNS, such as Tailscale name resolution, is excluded from
ordinary Internet DNS classification. Inspect `resolvectl status` for details.

## VPN/DNS indicators

The VPN icon distinguishes local VPN, assumed router VPN, no local VPN, and
unavailable status. Local VPN takes priority, but tooltip retains router context.
Router VPN is inferred from `vpn.routerManagedSsids`, not verified router health.
NetworkManager WireGuard/VPN profiles are detected on any network; standalone
WireGuard outside NetworkManager is not detected.

| DNS dot | Category |
| --- | --- |
| Mint | NextDNS |
| Blue | Router DNS; requires physical-interface gateway evidence |
| Neutral | Quad9, VPN DNS, or other DNS |
| Purple | Mixed categories |
| Muted red | Unavailable |

Colors identify resolver categories, **not security guarantees**.

## School OpenFortiVPN

Set these global `vpn` options in `bar-local.json`:

| Option | Default | Meaning |
| --- | --- | --- |
| `schoolService` | `""` | System service, e.g. `openfortivpn@Unistra.service`; empty disables detection and queries. Requires `Type=notify`. |
| `schoolInterface` | `ppp0` | Dedicated school PPP interface; must not identify an unrelated tunnel. |
| `schoolName` | `School VPN` | Tooltip label, e.g. `Unistra`. |

Every two seconds, the shared service checks systemd readiness and the configured
PPP interface's up/address state. Tooltip states: connected, connecting, stopping,
failed, disconnected, or unavailable. Process presence alone is insufficient;
tunnel evidence is not an end-to-end connectivity test.

- Established school tunnel: `󰑴`, using the existing connected-VPN color.
- School tunnel plus configured router-VPN Wi-Fi: amber `󰀦`, warning of possible
  nested tunneling and extra overhead. Actual nesting is not verified.
- Away from configured router-VPN networks: school/local VPNs are still detected.
  Multiple local tunnels are listed without a router-nesting warning.

School detection is read-only: no credential reads, service starts/stops, routing,
DNS, or VPN configuration changes. It does not presume school DNS is in use.
