function parseStatus(text) {
    let data;
    try { data = JSON.parse(text); } catch (_) { return null; }
    const tx = data?.transmitters;
    if (!tx || typeof tx !== "object" || Array.isArray(tx)) return null;
    const result = [];
    for (const id of Object.keys(tx).sort()) {
        const item = tx[id];
        if (!/^tx[1-4]$/.test(id) || !item || typeof item.charging !== "boolean"
            || (item.level !== null && (!Number.isInteger(item.level) || item.level < 1 || item.level > 7))) return null;
        result.push({id: id, level: item.level, charging: item.charging});
    }
    return result;
}

function batteryIcon(level) {
    return ["󰁹", "󰂁", "󰁿", "󰁾", "󰁼", "󰁺", "󰂎"][level - 1] || "󰂑";
}
