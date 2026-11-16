function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function text(value) {
    return typeof value === "string" && !value.includes("\0");
}

function integer(value, minimum, maximum) {
    return Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}

function emptyHistory() {
    return { version: 1, nextId: 1, entries: [] };
}

function parseNotification(line, id, receivedAt) {
    let message;
    try {
        message = JSON.parse(line);
    } catch (_) {
        return null;
    }
    if (!object(message) || message.type !== "method_call"
        || message.path !== "/org/freedesktop/Notifications"
        || message.interface !== "org.freedesktop.Notifications" || message.member !== "Notify"
        || !object(message.payload) || message.payload.type !== "susssasa{sv}i")
        return null;
    const args = message.payload.data;
    if (!Array.isArray(args) || args.length !== 8
        || !text(args[0]) || !integer(args[1], 0, 4294967295)
        || !text(args[2]) || !text(args[3]) || !text(args[4])
        || !Array.isArray(args[5]) || args[5].length % 2 !== 0 || !args[5].every(text)
        || !object(args[6]) || !integer(args[7], -2147483648, 2147483647)
        || !integer(id, 1, Number.MAX_SAFE_INTEGER - 1) || !integer(receivedAt, 0, 8640000000000000))
        return null;
    if (Object.prototype.hasOwnProperty.call(args[6], "transient")) {
        const transient = args[6].transient;
        if (!object(transient) || transient.type !== "b" || transient.data !== false)
            return null;
    }
    return { id: id, receivedAt: receivedAt, appName: args[0] || "Notification",
        summary: args[3], body: args[4], appIcon: args[2] };
}

function decodeHistory(source) {
    let value;
    try {
        value = JSON.parse(source);
    } catch (_) {
        return null;
    }
    if (!object(value) || value.version !== 1 || !integer(value.nextId, 1, Number.MAX_SAFE_INTEGER)
        || !Array.isArray(value.entries))
        return null;
    const ids = new Set();
    const entries = [];
    for (const entry of value.entries) {
        if (!object(entry) || !integer(entry.id, 1, value.nextId - 1) || ids.has(entry.id)
            || !integer(entry.receivedAt, 0, 8640000000000000)
            || !text(entry.appName) || entry.appName === "" || !text(entry.summary)
            || !text(entry.body) || !text(entry.appIcon))
            return null;
        ids.add(entry.id);
        const normalized = { id: entry.id, receivedAt: entry.receivedAt, appName: entry.appName,
            summary: entry.summary, body: entry.body, appIcon: entry.appIcon };
        if (entry.updatedAt !== undefined) {
            if (!integer(entry.updatedAt, entry.receivedAt, 8640000000000000))
                return null;
            normalized.updatedAt = entry.updatedAt;
        }
        if (entry.revision !== undefined) {
            if (!integer(entry.revision, 1, Number.MAX_SAFE_INTEGER))
                return null;
            normalized.revision = entry.revision;
        }
        if (entry.urgency !== undefined) {
            if (!integer(entry.urgency, 0, 2))
                return null;
            normalized.urgency = entry.urgency;
        }
        if (entry.imageExpected !== undefined) {
            if (typeof entry.imageExpected !== "boolean")
                return null;
            normalized.imageExpected = entry.imageExpected;
        }
        if (entry.thumbnail !== undefined) {
            if (typeof entry.thumbnail !== "string" || (entry.thumbnail !== "" && !/^notification-[A-Za-z0-9]{10}\.png$/.test(entry.thumbnail)))
                return null;
            normalized.thumbnail = entry.thumbnail;
        }
        entries.push(normalized);
    }
    return { version: 1, nextId: value.nextId, entries: entries };
}
