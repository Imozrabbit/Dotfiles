function parseProfiles(text) {
    if (typeof text !== "string" || text.length > 262144)
        return null;
    if (text === "")
        return [];
    const lines = (text.endsWith("\n") ? text.slice(0, -1) : text).split("\n");
    const profiles = [], paths = new Set();
    for (const line of lines) {
        const fields = [""];
        for (let index = 0; index < line.length; ++index) {
            const character = line[index];
            if (character === "\\") {
                const next = line[++index];
                if (next !== "\\" && next !== ":")
                    return null;
                fields[fields.length - 1] += next;
            } else if (character === ":") {
                fields.push("");
            } else {
                fields[fields.length - 1] += character;
            }
        }
        if (fields.length !== 6 || /[\x00-\x1f\x7f]/.test(line))
            return null;
        const [name, uuid, type, active, state, path] = fields;
        if (name === "" || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(uuid) || type === "")
            return null;
        if (active === "yes") {
            if (!["activated", "activating", "deactivating"].includes(state)
                || !/^\/org\/freedesktop\/NetworkManager\/ActiveConnection\/[0-9]+$/.test(path) || paths.has(path))
                return null;
            paths.add(path);
        } else if (active !== "no" || state !== "" || path !== "") {
            return null;
        }
        if (type === "wireguard" || type === "vpn")
            profiles.push({ name, uuid, state, path });
    }
    return profiles;
}

function selectRequest(profiles, defaultProfile) {
    const active = profiles.filter(profile => profile.path !== "");
    if (active.length)
        return { operation: "down", targets: active.map(profile => profile.path), error: "" };
    if (!defaultProfile)
        return { operation: "", targets: [], error: "Default VPN profile not configured" };
    const matches = [...new Set(profiles.filter(profile => profile.name === defaultProfile).map(profile => profile.uuid))];
    if (matches.length !== 1)
        return { operation: "", targets: [], error: "Default VPN profile " + (matches.length ? "name is ambiguous: " : "not found: ") + defaultProfile };
    return { operation: "up", targets: matches, error: "" };
}
