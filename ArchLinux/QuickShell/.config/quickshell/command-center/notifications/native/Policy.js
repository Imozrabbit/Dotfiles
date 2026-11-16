function localImage(source) {
    if (typeof source !== "string" || /[\x00-\x1f\x7f]/.test(source))
        return "";
    return (source.startsWith("/") && !source.startsWith("//")) || source.startsWith("file:///")
        || source.startsWith("image://") || source.startsWith("qrc:/") ? source : "";
}

function duration(urgency, requested) {
    if (urgency === 2)
        return 0;
    return typeof requested === "number" && isFinite(requested) && requested > 0
        ? Math.min(2147483647, Math.max(1, Math.floor(requested))) : urgency === 0 ? 4000 : 9000;
}

function code(text) {
    if (typeof text !== "string" || !/\b(?:code|passcode|verification|otp|2fa|authentication)\b/i.test(text))
        return "";
    const match = text.match(/\b\d{4,8}\b/);
    return match ? match[0] : "";
}

function safeText(value) {
    return typeof value === "string" ? value.replace(/\0/g, "\ufffd") : "";
}

function snapshot(notification) {
    const hints = notification.hints || {};
    const body = safeText(notification.body);
    const tag = body.match(/<img\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1[^>]*>/i);
    const candidate = notification.image || hints["image-path"] || hints.image_path || (tag ? tag[2] : "");
    const transient = Object.prototype.hasOwnProperty.call(hints, "transient")
        ? hints.transient !== false : notification.transient === true;
    const summary = safeText(notification.summary);
    // A leading image on its own line must not leave an empty caption line.
    const message = body.replace(/^[ \t]*<img\b[^>]*>[ \t]*\r?\n/i, "")
        .replace(/<img\b[^>]*>/gi, "");
    return {
        appName: safeText(notification.appName) || "Notification", summary, body: message,
        appIcon: localImage(notification.appIcon), source: localImage(candidate), imageExpected: !!candidate,
        urgency: [0, 1, 2].includes(notification.urgency) ? notification.urgency : 1,
        transient, resident: notification.resident === true, timeout: notification.expireTimeout,
        hasInlineReply: notification.hasInlineReply === true,
        inlineReplyPlaceholder: safeText(notification.inlineReplyPlaceholder),
        actions: (notification.actions || []).filter(action => typeof action.identifier === "string" && typeof action.text === "string")
            .map(action => ({ id: action.identifier, text: action.text })),
        code: code(summary + " " + message)
    };
}
