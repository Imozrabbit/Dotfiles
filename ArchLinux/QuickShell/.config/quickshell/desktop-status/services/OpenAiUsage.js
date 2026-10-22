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
    if (!Number.isSafeInteger(data.bankedResets) || data.bankedResets < 0)
        data.bankedResets = null;
    return data;
}

function remaining(window) {
    return window ? Math.max(0, Math.min(100, 100 - window.usedPercent)) : null;
}
