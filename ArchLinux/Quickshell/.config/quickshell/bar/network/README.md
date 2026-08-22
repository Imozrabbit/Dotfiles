# Network module

## Overview

This directory supplies bar network and VPN indicators, hover tooltip, and Wi-Fi control menu.

For normal use: bar shows connection icon, current download/upload rates, and VPN status icon. Hover shows connection, VPN, and DNS details after short delay. Click opens Wi-Fi menu, where user can turn Wi-Fi radio on/off, disconnect active Wi-Fi, scan, activate saved profiles, join new networks, or open NetworkManager advanced editor.

Two sources intentionally coexist:

- `NetworkStats.qml` uses Linux kernel route/counter data for bar traffic and current default-route interface.
- `wifi/` uses NetworkManager through `nmcli` for Wi-Fi radio, profiles, scans, and mutations.

“Saved” means NetworkManager already has wireless connection profile for SSID. It does **not** mean access point currently visible or reachable. “Available” means scan found visible access point, after entries with saved SSID are removed. Multiple access points sharing SSID become one available row: strongest BSSID (access-point radio identifier) wins.

## Directory tree

```text
network/
├── NetworkDetails.qml              # On-demand IPv4 address and Wi-Fi frequency
├── NetworkStats.qml                # Default route, byte counters, rates, bar state
├── NetworkTooltip.qml              # Hover popup
├── NetworkUsage.qml                # Click/hover bar widget; owns overlays
├── README.md
├── vpn/
│   ├── VpnDnsStatus.qml            # Active VPN query and laptop DNS mapping
│   └── VpnIndicator.qml            # Bar separator/icon and status ownership
└── wifi/
    ├── WifiMenu.qml                 # Full-screen overlay lifecycle and focus
    ├── WifiController.qml           # Menu state machine and service orchestration
    ├── WifiStyle.qml                # Theme-to-menu semantic style mapping
    ├── WifiUtils.js                 # Shell quoting, signal/security helpers
    ├── services/
    │   ├── WifiActionRunner.qml     # nmcli connection/radio actions
    │   ├── WifiScanner.qml          # Scan and strongest-SSID model
    │   ├── SavedNetworksService.qml # Saved NetworkManager Wi-Fi profiles
    │   └── WifiStatusService.qml    # Current Wi-Fi state and disk cache
    └── ui/
        ├── WifiMenuCard.qml         # Card composition
        ├── ConnectionSummary.qml    # Radio toggle, live connection, disconnect
        ├── NetworkListPage.qml      # Saved/available lists and rescan
        ├── CredentialsPage.qml      # Personal/enterprise credential form
        ├── SavedNetworkRow.qml      # One saved profile row
        ├── AvailableNetworkRow.qml  # One scanned AP row
        └── controls/
            ├── MenuButton.qml       # Reusable menu button
            └── PillField.qml        # Reusable credential input
```

## What appears on screen

- **Bar:** connection icon, down-arrow rate, up-arrow rate, and VPN icon. Offline, wired, unknown, and five Wi-Fi signal ranges have separate Nerd Font glyphs. VPN icon uses online color while active and neutral separator color otherwise.
- **Tooltip:** `Disconnected`, Wi-Fi SSID, Ethernet, or generic Network title. Online Wi-Fi adds signal and frequency; all online links add interface, IPv4 CIDR address, gateway, VPN connection, and DNS provider. Unknown values show `N/A`.
- **Menu:** bottom-right card, 10 px from right and 48 px above bottom. `Networks` expands scan lists. Connection summary has Wi-Fi toggle and active Wi-Fi disconnect button. Error output shows final ten captured lines; internal `__EXIT:<status>` marker may occupy one line.

## Startup and runtime flow

1. `shell.qml` creates one `Network.NetworkStats` as `root.networkStats`.
2. It passes stats properties and `refreshDetails()` request signal to `Network.NetworkUsage`.
3. `NetworkUsage.qml` owns `NetworkTooltip`, `Vpn.VpnIndicator`, and `Wifi.WifiMenu`; only this module toggles menu visibility.
4. `NetworkStats` reloads `/proc/net/route` every 1000 ms, selects lowest-metric valid IPv4 default route, then reloads `/proc/net/dev` and computes byte-per-second deltas.
5. Hover enters bar: `NetworkUsage` requests details immediately and opens tooltip after 300 ms, unless menu is open. `NetworkDetails` runs `ip` and, for Wi-Fi, `iw` only then.
6. Click toggles menu. `WifiMenu` reports visibility to `WifiController`; opening refreshes live status and saved profiles. Controller scanned list stays collapsed until user chooses `Networks`.
7. `VpnDnsStatus` queries active NetworkManager connections every two seconds. Successful state maps active VPN to Proton DNS and inactive VPN to NextDNS.

### Network monitor flow

`NetworkStats.selectDefaultRoute()` parses `/proc/net/route`. Candidate must be default destination, have nonzero gateway, be an up/gateway route, and have lower metric than prior candidate. Gateway is converted from kernel little-endian hex to dotted IPv4.

`updateInterface()` resets details, rates, online state, and prior counter sample whenever interface changes. `parseInterfaceCounters()` finds selected interface in `/proc/net/dev`, reads RX byte field 0 and TX byte field 8, then `sampleInterfaceCounters()` divides nonnegative counter deltas by actual elapsed wall time. First sample and counter reset yield zero rates while valid counters keep link online. Missing interface, invalid data, route read failure, and counter read failure yield stable zero/offline fallback.

`Quickshell.Networking` identifies selected device type and connected Wi-Fi network. It provides `connectionType`, SSID, and normalized signal strength; kernel files remain source for route and transfer totals. Tooltip detail commands reject stale output if interface/type changed while command ran.

### VPN indicator flow

`VpnIndicator.qml` owns one `VpnDnsStatus` service and exposes its state to `NetworkUsage`. The service directly runs a two-second-bounded `nmcli` active-connection query, accepts `wireguard` and `vpn` connection types, and selects the first active VPN name. It does not run `resolvectl`: this laptop uses Proton DNS whenever VPN is active and NextDNS otherwise, so DNS name is derived from validated VPN state.

The indicator remains one glyph separated from upload rate. A successful query with no VPN uses neutral separator color and reports `VPN: Disconnected`, `DNS: NextDNS`; active VPN uses online color and reports its connection name plus `DNS: Proton`. Failed queries clear stale state and make both tooltip values `N/A`.

## Wi-Fi menu flow

### State and controller

`WifiMenu.qml` is full-screen transparent `PanelWindow` in Wayland overlay layer. It requests exclusive keyboard focus while visible. `Esc`, click outside card, and invoking Advanced Settings call `dismiss()`; embedded mode emits `closeRequested`, standalone mode exits Quickshell. Closing resets page, target SSID, and password only; it does not cancel running process or clear username, models, status, or error text.

`WifiController.qml` owns menu state, page index (`0` list, `1` credentials), pending profile identifiers, status/error messages, debounce, polling, and service composition. `isBusy` aliases action runner. Mutation controls are disabled while an action runs; rescan is disabled during scans or actions, but network rows remain enabled during scans. A shared 20-second watchdog warns `Operation timed out - please wait`; it does not terminate command. If scan and action overlap, either completion stops shared watchdog even if other process continues. Collapsing network list also clears `scanRunning` without terminating already-started scan process.

### Services and models

- `WifiStatusService`: reads cache once with `FileView`, then runs `nmcli` status query. Live result wins cache. It exposes Wi-Fi enabled state, active UUID, SSID, signal, and IPv4 source address. Resolved changed state writes cache detached.
- `SavedNetworksService`: finds NetworkManager `802-11-wireless` profiles. Its list model stores `{ uuid, ssid, name }`; its SSID lookup stores the first profile as `{ uuid }`.
- `WifiScanner`: scans visible APs, parses `BSSID:SSID:SECURITY:SIGNAL`, ignores incomplete/hidden rows, and retains strongest entry per SSID.
- Controller rebuilds `availableModel` after scan and saved refreshes, excluding all scanned SSIDs present in saved lookup. This handles either process finishing first.
- `WifiActionRunner`: serializes mutations with `busy`, captures combined stdout/stderr plus exit marker, routes password-required output separately, delays refresh 1500 ms after success, and asks controller to refresh after generic failure.

### Connection flows

| User action | Flow |
|---|---|
| Saved row | `nmcli -w 15 connection up uuid <uuid>`. Missing UUID reports `Invalid connection`. Exact English output `Secrets were required` or `No suitable secrets` opens credentials page using controller's retained `targetIsEnterprise` value; saved profiles do not currently carry their security type into this path. Unmatched or localized secret errors follow generic failure path. |
| Saved personal profile after password page | Updates `802-11-wireless-security.key-mgmt` to `wpa-psk`, updates PSK, activates UUID. |
| New personal secured network | Password page, then `nmcli -w 20 dev wifi connect <ssid> password <password>`. If a saved profile now exists for SSID, controller activates saved UUID instead. |
| New open network | No credential page; runs `nmcli -w 20 dev wifi connect <ssid>`. |
| New enterprise network | Username/password page. Action deletes profile by same ID first, creates Wi-Fi profile with `wpa-eap`, PEAP, MSCHAPv2, identity, password, then activates it with 25 s wait. A profile already listed under Saved follows Saved-row behavior instead. |
| New profile failure | Action cleanup deletes connection **by ID/SSID** and returns original failure status. This removes failed/half-created profile; it can also remove pre-existing same-ID profile in enterprise pre-delete flow. |
| Toggle radio | `nmcli radio wifi off` or `on`. |
| Disconnect | `nmcli connection down uuid <active UUID>`; missing UUID reports `No active connection`. |
| Advanced Settings | detached `nm-connection-editor`, then menu dismisses immediately. |

Every value interpolated by QML into a `bash -c` command passes through `WifiUtils.shellQuote()`. Values discovered inside service scripts use quoted shell variables. This protects shell word boundaries and prevents shell injection, including through embedded single quotes. It does **not** hide credentials: password-bearing commands can be visible to local process inspection while running. Do not log generated commands or raw process output outside current error UI.

## Public component interfaces

### Shell ↔ monitor/widget

`shell.qml` constructs `NetworkStats` and binds these `NetworkUsage` required properties:

```qml
downloadBps, uploadBps, online, connectionType, signalPercent
interfaceName, networkName, gatewayAddress, ipAddressCidr, frequencyMhz
onDetailsRequested: root.networkStats.refreshDetails()
```

`NetworkStats` public output: `interfaceName`, `downloadBps`, `uploadBps`, `online`, readonly `connectionType`, `signalPercent`, `networkName`, `gatewayAddress`, `ipAddressCidr`, `frequencyMhz`, plus `refreshDetails()`.

`NetworkUsage` requires all listed display properties and `Core.Theme`, emits `detailsRequested`, and internally owns overlays. Do not instantiate competing menu/tooltip owners in `shell.qml`.

### Widget ↔ tooltip/menu

`NetworkUsage` supplies `NetworkTooltip` its anchor, connection fields, VPN/DNS state, and theme. Tooltip accepts only presentation data; it never runs commands.

`NetworkUsage` supplies `WifiMenu` with `standalone: false` and theme. `WifiMenu.closeRequested` is handled by setting its `visible` false. For separate config use, default `standalone: true` makes dismissal call `Qt.quit()`.

`VpnIndicator` requires `Core.Theme` and exposes readonly `vpnActive`, `vpnName`, `dnsName`, and `statusKnown`. `VpnDnsStatus` owns collection; indicator owns only bar presentation.

### Controller ↔ UI/services

UI receives `controller` and `style`. It invokes controller functions (`startScanToggle`, `rescanNow`, `connectSaved`, `selectNetwork`, `submitCredentials`, `showNetworkList`, `toggleWifi`, `disconnectNetwork`, `openAdvancedEditor`); the credentials page also writes controller fields `enteredUser` and `enteredPass`. Services expose state, models, functions, and relevant lifecycle signals to controller; services do not manipulate UI pages.

## Commands, files, and dependencies

| Item | Used by | Purpose |
|---|---|---|
| NetworkManager service | all `wifi/services` | Owns radio, profiles, activation, scanning. Must be running. |
| `nmcli` | all Wi-Fi services, `vpn/VpnDnsStatus` | Wi-Fi status/actions and active VPN detection. |
| `bash` | Wi-Fi services | Executes compound commands, redirection, cleanup. |
| `awk` | status/saved services | Filters active wireless connection and profile UUIDs; extracts source IP. |
| `head` | status service | Selects first SSID line from a saved connection profile. |
| `mkdir` | status service | Creates cache directory before writing status JSON. |
| `ip` | `NetworkDetails`, status service | JSON IPv4 tooltip address; source address selected by route to `1.1.1.1`. |
| `iw` | `NetworkDetails` | `iw dev <interface> link` frequency for Wi-Fi tooltip. |
| `nm-connection-editor` | action runner | Advanced NetworkManager editor, launched detached. |
| `/proc/net/route` | `NetworkStats` | IPv4 default route and gateway. |
| `/proc/net/dev` | `NetworkStats` | Per-interface RX/TX cumulative bytes. |
| `$HOME/.cache/quickshell/wifi_status.json` | status service | Best-effort last known Wi-Fi state cache. Created through `mkdir -p`; malformed cache is ignored. |
| Quickshell `Networking`, `Io`, `Wayland` | monitor/menu | Device data, `Process`/`FileView`, Wayland overlay. |
| Qt Quick, Layouts, Controls | all UI | QML display, layout, controls. |
| `Qt5Compat.GraphicalEffects` | card/list | Drop shadow and busy-indicator color overlay. |
| `JetBrainsMono Nerd Font Propo` | bar/menu icons | Icon glyphs. |
| `Atkinson Hyperlegible Next` | tooltip/menu text | Text. Missing fonts cause fallback-font glyph/text changes. |

## Timing

- Route and rate sample: every **1000 ms**.
- VPN status query: every **2000 ms**, with **2-second** `nmcli` wait bound.
- Tooltip delay: **300 ms** after hover begins.
- Menu status poll: every **5000 ms**, only while menu visible and neither scan nor action active; no immediate timer trigger.
- Menu open: immediately refreshes status and saved profiles. Component creation also refreshes status and schedules saved refresh.
- Scan request: **500 ms** debounce after expand/rescan.
- Process watchdog: **20000 ms**, advisory only.
- Status message expiry: **3200 ms**.
- Successful action refresh: **1500 ms** after completion.

## Error and fallback behavior

- Bar considers route/counter availability, not connectivity test. `online` means active default-route interface with readable valid counters; it does not prove internet can reach a host.
- No valid default route, unreadable proc files, missing counter row, or invalid numbers leave zero rates and offline state. Counter reset yields zero rates for that sample while valid counters keep link online.
- Tooltip omits rows while offline; missing values display `N/A`. `ip` JSON parse failure clears IPv4; `iw` mismatch/missing frequency becomes `N/A`.
- Wi-Fi cache is optional. Invalid JSON/type fields are ignored; live `nmcli` state supersedes cache.
- VPN query failure clears stale VPN state and exposes unknown VPN/DNS values; successful empty VPN result means disconnected VPN with NextDNS.
- Expanding `Networks` while Wi-Fi is disabled reports `WiFi is off`; rescan returns without starting a scan. Empty completed scan with no saved profiles gives `No networks found`; scan nonzero exit gives `Scan failed`.
- Generic failed actions show `Connection failed` and final ten captured lines, potentially including internal exit marker. NetworkManager secret errors show `Password required` and open credential page. Action process abnormal nonzero exit with no collected result reports generic failure.

## Common edits

- Bar colors, tooltip colors/sizes, font names: `core/Theme.qml` network section (lines 71–87) and general typography (15–20).
- Bar layout, rate format, hover delay, icon thresholds: `NetworkUsage.qml`.
- VPN polling and DNS mapping: `vpn/VpnDnsStatus.qml`; VPN glyph/layout: `vpn/VpnIndicator.qml`.
- Route selection, 1-second cadence, counter logic: `NetworkStats.qml`.
- Tooltip labels/rows and anchoring: `NetworkTooltip.qml`; on-demand commands: `NetworkDetails.qml`.
- Menu placement, standalone behavior, dismissal/focus: `wifi/WifiMenu.qml`.
- Polling, page transitions, saved-vs-available rule, statuses: `wifi/WifiController.qml`.
- NetworkManager command behavior: matching file under `wifi/services/`.
- Wi-Fi visual tokens: `wifi/WifiStyle.qml`; card/pages/rows/controls: `wifi/ui/`.

## Safe change boundaries

- Keep bar monitoring and Wi-Fi control separate: route/counter data must not be replaced with `nmcli` unless intentional behavior change.
- Preserve `NetworkUsage` ownership of tooltip and menu; `shell.qml` only wires data.
- Keep VPN collection in `VpnDnsStatus` and presentation in `VpnIndicator`; DNS mapping intentionally follows this laptop's VPN state.
- Preserve `WifiMenu` overlay layer, exclusive keyboard focus, outside-click check, and `standalone` distinction.
- Keep `WifiController` as sole coordinator for pages, models, timers, and action outcomes. UI should emit intent, services should collect/mutate state.
- Keep saved-profile filtering after **both** scan and saved refresh paths.
- Preserve shell quoting for every dynamic `bash -c` value and failure cleanup semantics. Test SSIDs containing spaces, colons, and single quotes after command changes.
- Do not poll faster or add continuous subprocesses; current configuration already has recurring route poll and visible-menu status poll.

## Debugging checklist

1. **No bar rates / Offline:** inspect `NetworkStats.qml`; run `cat /proc/net/route`, `cat /proc/net/dev`. Confirm valid default route and selected interface counter row.
2. **Wrong interface/gateway:** inspect `selectDefaultRoute()` in `NetworkStats.qml`; run `ip route` and compare default-route metrics.
3. **Tooltip lacks IPv4/frequency:** inspect `NetworkDetails.qml`; run `ip -j -4 address show dev <interface>` and `iw dev <interface> link`. Frequency only applies when Quickshell reports device type Wi-Fi.
4. **Wrong bar icon/SSID/signal:** inspect `NetworkStats.qml` Quickshell `Networking` bindings and `NetworkUsage.qml` thresholds; confirm Nerd Font installed.
5. **Menu never opens/closes unexpectedly/focus issue:** inspect `NetworkUsage.qml` toggle and `wifi/WifiMenu.qml` visibility, `WlrLayershell`, `dismiss()`.
6. **Status stale or wrong:** inspect `WifiStatusService.qml`; run `nmcli -g WIFI radio`, `nmcli -g UUID,TYPE,STATE connection show --active`, and inspect cache path. Delete cache only for debugging; it is recreated.
7. **Saved list wrong:** inspect `SavedNetworksService.qml`; run `nmcli -t -f UUID,TYPE connection show` and `nmcli -g 802-11-wireless.ssid,connection.id connection show uuid <uuid>`.
8. **Scan missing/duplicate rows:** inspect `WifiScanner.qml` and controller `rebuildAvailableModel()`; run `nmcli -g BSSID,SSID,SECURITY,SIGNAL dev wifi list --rescan yes`.
9. **Cannot connect / password loop:** inspect `WifiActionRunner.qml` and controller action signals. Use `nmcli --ask connection up uuid <uuid>` or `nmcli --ask dev wifi connect <ssid>` where supported; never paste passwords into command line. Check NetworkManager logs and whether profile cleanup removed failed SSID profile. For saved-profile secret prompts, also inspect retained `targetIsEnterprise` state.
10. **Menu visual effect/module load error:** inspect `WifiMenuCard.qml`/`NetworkListPage.qml`; verify `Qt5Compat.GraphicalEffects`, both configured fonts, and imports.
11. **Wrong VPN icon or tooltip DNS:** inspect `vpn/VpnDnsStatus.qml`; run `nmcli --wait 2 --terse --escape no --fields NAME,TYPE connection show --active`. Confirm active Proton connection reports `wireguard` or `vpn`.

## Runtime test checklist

- Start changed config with `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/Quickshell/.config/quickshell/bar`; confirm no QML import/runtime errors.
- With route active, verify icon, interface-specific rates, and one-second rate updates. Disconnect route and verify zero/offline fallback.
- With VPN off, verify VPN icon uses neutral separator color and tooltip shows `VPN: Disconnected`, `DNS: NextDNS`. Enable Proton VPN, wait up to two seconds, and verify online color, connection name, and `DNS: Proton`.
- Hover 300 ms: check title, gateway, IPv4; on Wi-Fi check signal and frequency. Move pointer away and verify tooltip closes. Click and verify tooltip remains hidden while menu open.
- Open menu: verify focus, `Esc`, outside click, Wi-Fi toggle, summary, and close behavior.
- Expand networks: verify saved profiles, scan result deduplication, and saved SSIDs excluded from Available. Rescan.
- Test saved activation, secured personal connection, open connection, enterprise credentials if environment supports it, disconnect, and advanced editor.
- Deliberately use wrong password on disposable/test profile: verify password/error route and failed new-profile cleanup. Do not test cleanup against profile user needs to keep.
- Verify cache updates after resolved status change and malformed cache does not crash menu.
