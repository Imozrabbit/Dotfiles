function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function tooltipText(value, fallback) {
    return typeof value === "string" ? value.slice(0, 512).replace(/[\x00-\x1f\x7f]/g, " ") : fallback;
}

function resolveConfig(text, previous) {
    const settings = {
        panel: { width: 300, height: 900 },
        toast: { width: 350, height: 0 },
        background: { color: "#0f1416", opacity: 0.4 },
        colors: {},
        media: { cavaEnabled: true, sourceNames: {} },
        padding: { left: 16, right: 16 },
        sections: [
            { id: "quickActions", enabled: true, spacingBefore: 12 },
            { id: "media", enabled: true, spacingBefore: 6 },
            { id: "sliders", enabled: true, spacingBefore: 12 },
            { id: "notifications", enabled: true, spacingBefore: 8 }
        ],
        quickActions: [],
        powerActions: [
            { id: "hibernate", tooltip: "Hibernate" },
            { id: "suspend", tooltip: "Suspend" },
            { id: "logout", tooltip: "Log out" },
            { id: "lock", tooltip: "Lock session" },
            { id: "reboot", tooltip: "Reboot" },
            { id: "poweroff", tooltip: "Power off" }
        ].map(action => ({
            id: action.id,
            tooltip: action.tooltip,
            enabled: true,
            command: action.id === "lock" ? "/usr/bin/loginctl lock-session" : "./power/actions/confirm.sh " + action.id
        })),
        sliders: [
            { type: "volume", length: 2, enabled: true },
            { type: "microphone", length: 1, enabled: true },
            { type: "brightness", length: 2, enabled: true }
        ]
    };
    let local;
    try {
        local = JSON.parse(text);
    } catch (_) {
        return previous || settings;
    }
    if (!isObject(local))
        return previous || settings;

    if (isObject(local.panel)) {
        for (const dimension of ["width", "height"]) {
            const value = local.panel[dimension];
            if (Number.isSafeInteger(value) && value > 0)
                settings.panel[dimension] = value;
        }
    }
    if (isObject(local.background)) {
        if (typeof local.background.color === "string" && /^#[0-9a-f]{6}$/i.test(local.background.color))
            settings.background.color = local.background.color;
        const opacity = local.background.opacity;
        if (typeof opacity === "number" && isFinite(opacity) && opacity >= 0 && opacity <= 1)
            settings.background.opacity = opacity;
    }
    if (isObject(local.toast)) {
        if (Number.isSafeInteger(local.toast.width) && local.toast.width > 0)
            settings.toast.width = local.toast.width;
        if (Number.isSafeInteger(local.toast.height) && local.toast.height >= 0)
            settings.toast.height = local.toast.height;
    }
    if (isObject(local.colors)) {
        for (const key of Object.keys(local.colors)) {
            const color = local.colors[key];
            if (typeof color === "string" && /^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i.test(color))
                settings.colors[key] = color;
        }
    }
    if (isObject(local.media) && typeof local.media.cavaEnabled === "boolean")
        settings.media.cavaEnabled = local.media.cavaEnabled;
    if (isObject(local.media) && isObject(local.media.sourceNames)) {
        const names = Object.create(null);
        for (const key of Object.keys(local.media.sourceNames)) {
            const name = local.media.sourceNames[key];
            if (key.trim() !== "" && key.length <= 256 && !/[\x00-\x1f\x7f]/.test(key)
                && typeof name === "string" && name.trim() !== "" && name.trim().length <= 128
                && !/[\x00-\x1f\x7f]/.test(name))
                names[key] = name.trim();
        }
        settings.media.sourceNames = names;
    }
    if (isObject(local.padding)) {
        const padding = Object.assign({}, settings.padding);
        for (const side of ["left", "right"]) {
            const value = local.padding[side];
            if (typeof value === "number" && isFinite(value) && value >= 0)
                padding[side] = value;
        }
        // Keep padding modest for compact control rows.
        if (padding.left + padding.right <= 64)
            settings.padding = padding;
    }
    if (Array.isArray(local.quickActions)) {
        settings.quickActions = local.quickActions.filter(entry => isObject(entry)
            && typeof entry.icon === "string" && entry.icon.trim() !== "" && entry.icon.length <= 128
            && !/[\x00-\x1f\x7f]/.test(entry.icon)
            && (entry.enabled === undefined || typeof entry.enabled === "boolean")
            && (entry.type === undefined || entry.type === "normal" || entry.type === "toggle")
            && (entry.active === undefined || typeof entry.active === "boolean"))
            .map(entry => {
                const action = {
                    id: ["network", "bluetooth", "vpn", "idle-inhibit", "localsend", "hyprsunset", "dnd"].includes(entry.id) ? entry.id : "",
                    enabled: entry.enabled === undefined ? true : entry.enabled,
                    icon: entry.icon.trim(),
                    tooltip: tooltipText(entry.tooltip, ""),
                    tooltipOn: tooltipText(entry.tooltipOn, null),
                    tooltipOff: tooltipText(entry.tooltipOff, null),
                    type: entry.type || "normal",
                    active: entry.active === true,
                    display: entry.display === "details" || (entry.id === "idle-inhibit" && entry.display !== "icon") ? "details" : "icon",
                    title: typeof entry.title === "string" ? entry.title.slice(0, 512).replace(/[\x00-\x1f\x7f]/g, " ") : "",
                    details: typeof entry.details === "string" ? entry.details.slice(0, 512).replace(/[\x00-\x1f\x7f]/g, " ") : ""
                };
                // Read legacy input during migration; explicit action fields always win.
                const options = Object.assign(Object.create(null), isObject(local[action.id]) ? local[action.id] : {}, entry);
                if (action.id === "vpn") {
                    const profile = options.defaultProfile;
                    action.defaultProfile = profile === undefined ? "CH-Zurich"
                        : typeof profile === "string" && profile.trim() !== "" && profile.length <= 256
                            && !/[\x00-\x1f\x7f]/.test(profile) ? profile : "";
                    action.profileNames = Object.create(null);
                    if (isObject(options.profileNames)) {
                        for (const key of Object.keys(options.profileNames)) {
                            const name = options.profileNames[key];
                            if (key.trim() !== "" && key.length <= 256 && !/[\x00-\x1f\x7f]/.test(key)
                                && typeof name === "string" && name.trim() !== "" && name.trim().length <= 128
                                && !/[\x00-\x1f\x7f]/.test(name))
                                action.profileNames[key] = name.trim();
                        }
                    }
                } else if (action.id === "localsend") {
                    const path = options.scriptPath;
                    action.scriptPath = path === undefined ? "~/.config/nftables/scripts/localsend-mode.py"
                        : typeof path === "string" && /^(?:\/|~\/).+/.test(path)
                            && path.length <= 4096 && !/[\x00-\x1f\x7f]/.test(path) ? path : "";
                } else if (action.id === "hyprsunset") {
                    action.temperature = Number.isSafeInteger(entry.temperature) && entry.temperature >= 1000 && entry.temperature <= 20000
                        ? entry.temperature : 4500;
                }
                return action;
            });
    }
    // Unchanged actions keep their preview state when other settings reload.
    if (previous && JSON.stringify(settings.quickActions) === JSON.stringify(previous.quickActions))
        settings.quickActions = previous.quickActions;
    if (Array.isArray(local.powerActions)) {
        const defaults = settings.powerActions;
        settings.powerActions = [];
        for (const entry of local.powerActions) {
            if (!isObject(entry) || (entry.enabled !== undefined && typeof entry.enabled !== "boolean"))
                continue;
            const fallback = defaults.find(action => action.id === entry.id);
            if (!fallback || settings.powerActions.some(action => action.id === entry.id))
                continue;
            const command = entry.command === undefined ? fallback.command : entry.command;
            settings.powerActions.push({
                id: entry.id,
                tooltip: tooltipText(entry.tooltip, fallback.tooltip),
                enabled: entry.enabled === undefined ? true : entry.enabled,
                command: typeof command === "string" && command.length <= 8192 && !command.includes("\u0000") ? command : ""
            });
        }
    }
    if (previous && JSON.stringify(settings.powerActions) === JSON.stringify(previous.powerActions))
        settings.powerActions = previous.powerActions;
    if (Array.isArray(local.sliders)) {
        settings.sliders = local.sliders.filter(entry => isObject(entry)
            && ["volume", "microphone", "brightness"].includes(entry.type)
            && (entry.enabled === undefined || typeof entry.enabled === "boolean"))
            .map(entry => ({
                type: entry.type,
                length: entry.length === 1 || entry.length === 2 ? entry.length : (entry.type === "microphone" ? 1 : 2),
                enabled: entry.enabled === undefined ? true : entry.enabled
            }));
    }
    if (previous && JSON.stringify(settings.sliders) === JSON.stringify(previous.sliders))
        settings.sliders = previous.sliders;
    if (Array.isArray(local.sections)) {
        const defaults = settings.sections;
        settings.sections = [];
        for (const entry of local.sections) {
            if (!isObject(entry))
                continue;
            const fallback = defaults.find(section => section.id === entry.id);
            if (!fallback || settings.sections.some(section => section.id === entry.id))
                continue;
            settings.sections.push({
                id: entry.id,
                enabled: typeof entry.enabled === "boolean" ? entry.enabled : true,
                spacingBefore: Number.isSafeInteger(entry.spacingBefore) && entry.spacingBefore >= 0 ? entry.spacingBefore : fallback.spacingBefore
            });
        }
    }
    if (previous && JSON.stringify(settings.sections) === JSON.stringify(previous.sections))
        settings.sections = previous.sections;
    return settings;
}
