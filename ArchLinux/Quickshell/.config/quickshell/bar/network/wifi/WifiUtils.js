.pragma library

// Pure WiFi helpers shared by backend services and presentation components.

// Commands are assembled for bash -c; quote every user or nmcli-provided value
// as one single-quoted shell word, including embedded single quotes.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function getSignalIcon(strength) {
    if (strength > 80)
        return "󰤨";
    if (strength > 60)
        return "󰤥";
    if (strength > 40)
        return "󰤢";
    if (strength > 20)
        return "󰤟";
    return "󰤯";
}

function securityIsEnterprise(security) {
    const value = String(security || "");
    return value.includes("802.1X") || value.includes("Enterprise");
}

function securityLabel(security, isEnterprise) {
    if (isEnterprise)
        return "Enterprise";
    const value = String(security || "").trim();
    if (value === "" || value === "--")
        return "Open";
    return "Secured";
}
