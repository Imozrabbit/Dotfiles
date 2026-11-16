function parseDisplays(text) {
    if (typeof text !== "string" || text.length > 65536)
        return null;
    const trimmed = text.trim();
    if (trimmed === "" || /^No displays found\.?$/i.test(trimmed))
        return [];
    const records = [];
    for (const block of trimmed.split(/\n\s*\n/)) {
        if (/^Invalid display\b/.test(block))
            continue;
        if (!/^Display \d+\r?\n/.test(block))
            return null;
        const bus = block.match(/^[ \t]*I2C bus:[ \t]*\/dev\/i2c-(\d+)[ \t]*$/m);
        const connector = block.match(/^[ \t]*DRM connector:[ \t]*(card\d+-([A-Za-z0-9_.-]{1,128}))[ \t]*$/m);
        const monitor = block.match(/^[ \t]*Monitor:[ \t]*([^\r\n]+)$/m);
        if (!bus || !connector || !monitor || Number(bus[1]) > 65535)
            return null;
        const identity = monitor[1].trim();
        if (identity === "" || identity.length > 1024 || /[\x00-\x1f\x7f]/.test(identity))
            return null;
        const model = identity.split(":").slice(1, -1).join(":").trim();
        records.push({
            id: connector[1] + "|" + identity,
            connector: connector[2],
            label: model ? model + " (" + connector[2] + ")" : connector[2],
            bus: Number(bus[1]),
            identity
        });
        if (records.length > 64)
            return null;
    }
    // Duplicate connections cannot be mapped unambiguously to a screen.
    return records.filter(record => records.filter(other => other.bus === record.bus).length === 1
        && records.filter(other => other.connector === record.connector).length === 1);
}

function parseValue(text) {
    if (typeof text !== "string" || text.length > 256)
        return null;
    const match = text.trim().match(/^VCP 10 C (\d+) (\d+)$/);
    if (!match)
        return null;
    const current = Number(match[1]);
    const maximum = Number(match[2]);
    if (!Number.isSafeInteger(current) || !Number.isSafeInteger(maximum) || maximum <= 0 || maximum > 65535 || current > maximum)
        return null;
    return { current, maximum, value: current / maximum * 100 };
}

function rawValue(percent, maximum) {
    if (!Number.isFinite(percent) || !Number.isInteger(maximum) || maximum < 1 || maximum > 65535)
        return null;
    return Math.max(1, Math.round(Math.max(1, Math.min(100, percent)) * maximum / 100));
}
