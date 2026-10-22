function parseStatus(text) {
    let data;
    try {
        data = JSON.parse(text);
    } catch (_) {
        return null;
    }
    if (!data || !Number.isInteger(data.battery) || data.battery < 0 || data.battery > 100
        || typeof data.charging !== "boolean" || (data.connection !== "wired" && data.connection !== "wireless"))
        return null;
    return { battery: data.battery, charging: data.charging, connection: data.connection };
}
