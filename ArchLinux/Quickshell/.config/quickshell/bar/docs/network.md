# Wi-Fi, DNS, and VPN

[Back to bar setup and configuration](../README.md)

## Per-network DNS

Expand a connected or saved Wi-Fi card to choose **Auto** (previously Default)
or a configured provider. Selection is pending until confirmed; Connect/Disconnect
remain separate actions.

- **Confirm:** save the pending choice, verify readback, and attempt live apply.
- **Test:** test the pending provider's servers without saving; disabled for Auto.
- **Cancel:** discard pending edits and restore the saved selection, without writes.

Closing the card or switching profiles also discards pending edits. Confirm applies:

- **Auto:** accepts network-advertised DNS for supported IPv4/IPv6 methods and disables per-connection DoT.
- **Quad9:** sets Quad9 IPv4/IPv6 addresses, ignores automatically supplied DNS, and disables per-connection DoT.
- **TLS providers:** preserve each `IP#TLS-hostname` and enable strict per-connection
  DoT. Switching back to Default/Quad9 clears this strict setting.
- Other configured providers use their specified addresses. Auto is built-in.

Disconnected profiles use the confirmed choice next time. No deliberate reconnect occurs.

Feedback reports whether settings were saved and applied. If live application
fails, reconnect when convenient. NetworkManager may require a running Polkit agent.

Existing custom DNS leaves provider segments unselected and remains unchanged until
you explicitly confirm a replacement. Unrecognized server formats are treated as
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
unmatched saved addresses appear as Custom. Recognition uses address sets, TLS
hostnames, and DoT mode, not stored provider IDs; equivalent definitions resolve
to the first matching entry. Existing opportunistic DoT remains Custom.

Validation happens before entries become selectable: unique lowercase IDs
(letters, digits, `_`, `-`; maximum 32 characters), labels up to 32 characters,
correct IPv4/IPv6 lists, and at least one address. IDs `automatic` and `custom`
are reserved. Limits: 32 providers, eight addresses per family. Malformed,
multicast, unspecified, and zone-qualified addresses are rejected with visible
configuration warnings. Private DNS addresses are allowed. Saving requires
addresses for every DNS-capable IP family enabled on that profile.

Optional `tls` must be a JSON boolean (default `false`). With `tls: true`, every
address must include `#TLS-hostname`; bare addresses, URI syntax, custom ports,
and malformed hostnames are rejected. With `tls: false`, only bare IPs are accepted.
Hostname case and IPv6 spelling are normalized; profile hostnames are never discarded.

### NextDNS over TLS

Add this `dns` section to host-local `bar-local.json`, replacing **all four**
`abcdef` placeholders with the profile ID from your NextDNS setup page. The list
replaces defaults, so Quad9 is included explicitly:

```json
{
  "dns": {
    "providers": [
      {
        "id": "nextdns",
        "label": "NextDNS",
        "tls": true,
        "ipv4": ["45.90.28.0#abcdef.dns.nextdns.io", "45.90.30.0#abcdef.dns.nextdns.io"],
        "ipv6": ["2a07:a8c0::#abcdef.dns.nextdns.io", "2a07:a8c1::#abcdef.dns.nextdns.io"]
      },
      {
        "id": "quad9",
        "label": "Quad9",
        "ipv4": ["9.9.9.9", "149.112.112.112"],
        "ipv6": ["2620:fe::fe", "2620:fe::9"]
      }
    ],
    "preferredProvider": "nextdns"
  }
}
```

Requires NetworkManager with `IP#hostname` DNS support, its `systemd-resolved`
DNS backend, and `busctl` for a read-only backend check before saving strict DoT.
Unsupported/unverifiable backends reject the save rather than silently ignoring
encryption. NetworkManager sets `connection.dns-over-tls=yes` (strict, no plaintext
fallback); blocked TCP port 853 can prevent resolution. Choose Default explicitly
when needed, for example to sign into a captive portal. No automatic downgrade.

The TLS hostname verifies the server certificate and selects the NextDNS account
profile; bare NextDNS IPs do not reproduce that configuration. Profile IDs belong
in local overrides, not shared defaults. Adding this provider/preference alone
does not migrate existing Wi-Fi settings or change Ethernet/VPN profiles.

### Manual provider tests

**Test** queries each pending provider server for `example.com`: UDP port 53 for
plain providers, or certificate- and hostname-verified TLS on TCP port 853.
Each server has a two-second timeout; failed TLS never retries over plaintext.
Results report responses, timeouts or errors, with **TLS verified** on TLS success.

Tests are manual and never change profiles or system DNS. They follow current
routing, including VPNs; blocked DNS or missing IPv6 can cause failures. UDP does
not establish resolver identity. Even verified TLS does not prove filtering,
privacy, future availability or which resolver applications currently use.

### Policy versus observed DNS

The selector shows saved/pending policy; live labels and the network tooltip
independently report resolver routing, even if the VPN icon is disabled. On an
active card, Auto may show **VPN DNS: NextDNS**, **Network DNS**, **Mixed DNS** or
**DNS unavailable**. On inactive cards, **Auto · Network DNS** describes the
action, not an observed connection. Live status never changes the selection.

Quad9 does not enable encryption. Strict DoT applies only to the selected Wi-Fi
link; VPN DNS can take precedence. A saved setting or successful reapply does
not prove live end-to-end TLS. VPN/Tailscale profiles and routes stay untouched;
domain-specific split DNS is excluded from ordinary Internet DNS classification.
Use `resolvectl status` to inspect routing.

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

Detection checks systemd readiness and the configured PPP interface's up/address
state, not just process presence. Tooltip shows connected, connecting, stopping,
failed, disconnected or unavailable; this is not an end-to-end connectivity test.

- Established school tunnel: `󰑴`, using the existing connected-VPN color.
- School tunnel plus configured router-VPN Wi-Fi: amber `󰀦`, warning of possible
  nested tunneling and extra overhead. Actual nesting is not verified.
- School/local VPNs are still detected away from home; multiple tunnels are listed.

School detection is read-only: no credential reads, service starts/stops, routing,
DNS, or VPN configuration changes. It does not presume school DNS is in use.
