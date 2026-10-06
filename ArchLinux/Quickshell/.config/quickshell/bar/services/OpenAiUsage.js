function validWindow(value) {
    return value === null || value && typeof value.usedPercent === "number" && isFinite(value.usedPercent) && value.usedPercent >= 0
        && (value.resetAt === null || Number.isSafeInteger(value.resetAt) && value.resetAt >= 0);
}

function parseStatus(text) {
    let data;
    try {
        data = JSON.parse(text);
    } catch (_) {
        return null;
    }
    if (!data || typeof data.plan !== "string" || typeof data.allowed !== "boolean" || typeof data.limitReached !== "boolean"
        || !Number.isSafeInteger(data.fetchedAt) || data.fetchedAt <= 0 || !validWindow(data.fiveHour) || !validWindow(data.weekly)
        || !data.fiveHour && !data.weekly)
        return null;
    return data;
}

function remaining(window) {
    return window ? Math.max(0, Math.min(100, 100 - window.usedPercent)) : null;
}

function displayText(display, snapshot, available) {
    const windows = display === "both" ? ["weekly", "fiveHour"] : [display === "fiveHour" ? "fiveHour" : "weekly"];
    return windows.map(name => {
        const left = available && snapshot ? remaining(snapshot[name]) : null;
        return (name === "weekly" ? "󰨳 " : "󰔛 ") + (left === null ? "N/A" : Math.round(left) + "%");
    }).join(" · ");
}

function countdown(resetAt, now) {
    if (resetAt === null || resetAt === undefined)
        return "unknown";
    if (resetAt <= now)
        return "reset due";
    const seconds = Math.ceil((resetAt - now) / 1000);
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor(seconds / 3600) % 24;
    const minutes = Math.floor(seconds / 60) % 60;
    if (days > 0)
        return days + "d " + hours + "h " + minutes + "m";
    return (hours > 0 ? hours + "h " : "") + minutes + "m " + seconds % 60 + "s";
}
