function splitFields(line) {
    const fields = [""];
    let escaped = false;
    for (const character of line) {
        if (escaped) {
            fields[fields.length - 1] += character;
            escaped = false;
        } else if (character === "\\") {
            escaped = true;
        } else if (character === ":") {
            fields.push("");
        } else {
            fields[fields.length - 1] += character;
        }
    }
    return escaped ? null : fields;
}

function parseConnections(text) {
    const connections = [];
    for (const line of String(text).split(/\r?\n/)) {
        if (!line.trim()) continue;
        const fields = splitFields(line);
        if (!fields || fields.length !== 4 || !fields[0] || !fields[2]) return null;
        connections.push({ name: fields[1], type: fields[2], device: fields[3] });
    }
    return connections;
}

function vpnState(connections, activeSsids, routerManagedSsids, school) {
    const router = activeSsids.some(ssid => routerManagedSsids.includes(ssid));
    const schoolConnected = school?.state === "connected";
    const names = (connections || []).filter(connection => connection.type === "wireguard" || connection.type === "vpn").map(connection => connection.name);
    if (schoolConnected) names.push(school.name + " (OpenFortiVPN)");
    const mode = names.length ? "vpn" : connections === null ? "unknown" : router ? "home" : "unprotected";
    if (router) names.push("Router VPN (assumed)");
    return { mode, name: names.join(", "), schoolConnected, nestedWarning: router && schoolConnected,
        schoolStatus: school ? school.name + ": " + school.state : "" };
}

function schoolState(serviceText, interfaceText, interfaceName) {
    if (serviceText === null) return "unavailable";
    const fields = {};
    for (const line of serviceText.trim().split(/\r?\n/)) {
        const index = line.indexOf("=");
        if (index < 1) return "unavailable";
        fields[line.slice(0, index)] = line.slice(index + 1);
    }
    if (fields.LoadState !== "loaded") return "unavailable";
    if (fields.ActiveState === "inactive") return "disconnected";
    if (fields.ActiveState === "failed") return "failed";
    if (fields.ActiveState === "deactivating") return "stopping";
    if (fields.ActiveState === "activating") return "connecting";
    // openfortivpn's notify unit reports ready after tunnel setup; simple units do not.
    if (fields.ActiveState !== "active" || fields.SubState !== "running" || fields.Type !== "notify" || interfaceText === null)
        return "unavailable";
    let interfaces;
    try { interfaces = JSON.parse(interfaceText); } catch (_) { return "unavailable"; }
    if (!Array.isArray(interfaces)) return "unavailable";
    const tunnel = interfaces.find(entry => entry && entry.ifname === interfaceName);
    return tunnel && Array.isArray(tunnel.flags) && tunnel.flags.includes("UP") && tunnel.flags.includes("POINTOPOINT")
        && Array.isArray(tunnel.addr_info) && tunnel.addr_info.some(address => address && address.scope === "global"
            && (address.family === "inet" || address.family === "inet6") && typeof address.local === "string" && address.local !== "")
        ? "connected" : "connecting";
}

function normalizeAddress(value) {
    let address = value.split("#")[0].split("%")[0].toLowerCase();
    if (/^\d+\.\d+\.\d+\.\d+$/.test(address)) {
        const parts = address.split(".");
        return parts.every(part => part.length <= 3 && Number(part) <= 255) ? parts.map(Number).join(".") : null;
    }
    if (address.includes(":") && address.includes(".")) {
        const separator = address.lastIndexOf(":");
        const ipv4 = normalizeAddress(address.slice(separator + 1));
        if (!ipv4) return null;
        const bytes = ipv4.split(".").map(Number);
        address = address.slice(0, separator + 1) + (bytes[0] * 256 + bytes[1]).toString(16)
            + ":" + (bytes[2] * 256 + bytes[3]).toString(16);
    }
    if (!/^[0-9a-f:]+$/.test(address) || !address.includes(":")) return null;
    const halves = address.split("::");
    if (halves.length > 2) return null;
    const left = halves[0] ? halves[0].split(":") : [];
    const right = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
    if (!left.concat(right).every(part => /^[0-9a-f]{1,4}$/.test(part))) return null;
    const missing = 8 - left.length - right.length;
    if (halves.length === 1 && missing !== 0 || halves.length === 2 && missing < 1) return null;
    return left.concat(halves.length === 2 ? Array(missing).fill("0") : [], right).map(part => parseInt(part, 16).toString(16)).join(":");
}

function parseDevices(text) {
    const devices = {};
    let device = null;
    for (const line of String(text).split(/\r?\n/)) {
        if (!line.trim()) continue;
        const fields = splitFields(line);
        if (!fields || fields.length < 2) return null;
        // nmcli does not escape IPv6 gateway colons on every version.
        fields[1] = fields.slice(1).join(":");
        if (fields[0] === "GENERAL.DEVICE") {
            if (!fields[1]) return null;
            device = { type: "", connected: false, gateways: [] };
            devices[fields[1]] = device;
        } else if (!device) return null;
        else if (fields[0] === "GENERAL.TYPE") device.type = fields[1];
        else if (fields[0] === "GENERAL.STATE") device.connected = /^100(?:\s|$)/.test(fields[1]);
        else if (/^IP[46]\.GATEWAY$/.test(fields[0]) && fields[1] && fields[1] !== "--") {
            const address = normalizeAddress(fields[1]);
            if (!address) return null;
            device.gateways.push(address);
        }
    }
    return devices;
}

function parseDns(text) {
    const rows = [];
    let recognized = false;
    let device = "";
    for (const line of String(text).split(/\r?\n/)) {
        if (!line.trim()) continue;
        const match = line.match(/^\s*(?:Global|Link \d+ \(([^)]+)\)):\s*(.*)$/);
        if (match) {
            recognized = true;
            device = match[1] || "";
        } else if (!recognized || !/^\s+\S/.test(line)) return null;
        for (const server of (match ? match[2] : line).trim().split(/\s+/)) {
            if (!server) continue;
            const address = normalizeAddress(server);
            if (!address) return null;
            rows.push({ device: device, server: server, address: address });
        }
    }
    return recognized ? rows : null;
}

function parseDnsStatus(text) {
    const sections = [];
    let section = null;
    let previousField = "";
    for (const line of String(text).split(/\r?\n/)) {
        if (!line.trim()) { previousField = ""; continue; }
        const header = line.match(/^(Global|Link \d+ \(([^)]+)\))\s*$/);
        if (header) {
            section = { device: header[2] || "", servers: [], fallback: [], domains: [], defaultRoute: false, dnsScope: false };
            sections.push(section);
            previousField = "";
            continue;
        }
        if (!section) return null;
        const field = line.match(/^\s*([A-Za-z][A-Za-z .]+):(?:\s+(.*)|\s*)$/);
        let value;
        if (field) {
            previousField = field[1];
            value = field[2] || "";
        } else if (/^\s+\S/.test(line) && previousField) value = line.trim();
        else return null;
        const tokens = value.trim().split(/\s+/).filter(token => token !== "");
        if (previousField === "DNS Servers" || previousField === "Fallback DNS Servers") {
            const target = previousField === "DNS Servers" ? section.servers : section.fallback;
            for (const server of tokens) {
                const address = normalizeAddress(server);
                if (!address) return null;
                target.push({ device: section.device, server: server, address: address });
            }
        } else if (previousField === "DNS Domain") section.domains.push(...tokens);
        else if (previousField === "Current Scopes") section.dnsScope = tokens.includes("DNS");
        else if (previousField === "Protocols") section.defaultRoute = tokens.includes("+DefaultRoute");
        else if (previousField === "Default Route") section.defaultRoute = value.trim() === "yes";
    }
    if (!sections.length) return null;
    const usable = sections.filter(entry => entry.servers.length && (entry.device === "" || entry.dnsScope));
    // A root routing domain wins over ordinary default DNS links. Split DNS
    // domains such as Tailscale's machine names do not serve general queries.
    const rootRoutes = usable.filter(entry => entry.domains.includes("~."));
    const selected = rootRoutes.length ? rootRoutes : usable.filter(entry => entry.device === "" || entry.defaultRoute);
    const rows = [];
    for (const entry of selected) rows.push(...entry.servers);
    if (!rows.length) {
        for (const entry of sections.filter(entry => entry.device === "")) rows.push(...entry.fallback);
    }
    return rows;
}

function classifyDns(rows, devices, connections) {
    if (!rows || !rows.length) return { kind: "unavailable", name: "Unavailable", servers: "" };
    const nextDns = ["45.90.28.0", "45.90.30.0", "2a07:a8c0:0:0:0:0:0:0", "2a07:a8c1:0:0:0:0:0:0"];
    const quad9 = ["9.9.9.9", "149.112.112.112", "2620:fe:0:0:0:0:0:fe", "2620:fe:0:0:0:0:0:9"];
    const kinds = [];
    const sources = [];
    for (const row of rows) {
        const device = devices?.[row.device];
        const vpn = (connections || []).some(connection => (connection.type === "wireguard" || connection.type === "vpn") && connection.device === row.device);
        const physical = device?.connected && (device.type === "ethernet" || device.type === "wifi");
        const source = vpn ? "vpn" : physical ? "network" : "other";
        if (!sources.includes(source)) sources.push(source);
        const kind = nextDns.includes(row.address) ? "nextdns" : quad9.includes(row.address) ? "quad9" : physical && device.gateways.includes(row.address) ? "router" : vpn ? "vpn" : "other";
        if (!kinds.includes(kind)) kinds.push(kind);
    }
    const kind = kinds.length > 1 ? "mixed" : kinds[0];
    const names = { nextdns: "NextDNS", quad9: "Quad9", router: "Router DNS", vpn: "VPN DNS", other: "Other DNS", mixed: "Mixed" };
    return { kind: kind, name: names[kind], source: sources.length > 1 ? "mixed" : sources[0], servers: rows.map(row => (row.device || "Global") + ": " + row.server).join("\n") };
}
