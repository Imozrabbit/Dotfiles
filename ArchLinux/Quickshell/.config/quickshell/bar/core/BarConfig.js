function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function applyFields(target, override, moduleNames) {
    if (!isObject(override))
        return;
    if (override.mode === "off" || override.mode === "always" || override.mode === "hover")
        target.mode = override.mode;
    if (typeof override.hoverToggleEnabled === "boolean")
        target.hoverToggleEnabled = override.hoverToggleEnabled;
    if (isObject(override.modules)) {
        for (const name of moduleNames) {
            if (typeof override.modules[name] === "boolean")
                target.modules[name] = override.modules[name];
        }
    }
}

function workspaceSettings(defaults, override) {
    const result = {
        minimumCount: defaults.minimumCount,
        itemSpacing: defaults.itemSpacing,
        normalLabels: Object.assign({}, defaults.normalLabels),
        specialLabels: Object.assign({}, defaults.specialLabels)
    };
    if (!isObject(override))
        return result;
    if (Number.isSafeInteger(override.minimumCount) && override.minimumCount >= 0 && override.minimumCount <= 50)
        result.minimumCount = override.minimumCount;
    if (typeof override.itemSpacing === "number" && isFinite(override.itemSpacing) && override.itemSpacing >= 0 && override.itemSpacing <= 100)
        result.itemSpacing = override.itemSpacing;
    if (isObject(override.normalLabels)) {
        for (const id of Object.keys(override.normalLabels)) {
            const label = override.normalLabels[id];
            if (/^[1-9]\d{0,3}$/.test(id) && typeof label === "string" && label.trim() !== "" && label.length <= 64)
                result.normalLabels[id] = label;
        }
    }
    if (isObject(override.specialLabels)) {
        for (const name of Object.keys(override.specialLabels)) {
            const label = override.specialLabels[name];
            if (/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(name) && typeof label === "string" && label.trim() !== "" && label.length <= 64)
                result.specialLabels[name] = label;
        }
    }
    return result;
}

function resolveConfig(defaults, text) {
    const result = {
        mode: defaults.mode,
        hoverToggleEnabled: defaults.hoverToggleEnabled,
        modules: Object.assign({}, defaults.modules),
        workspaceDisplay: workspaceSettings(defaults.workspaceDisplay, null),
        monitors: {}
    };
    let local;
    try {
        local = JSON.parse(text);
    } catch (_) {
        return result;
    }
    if (!isObject(local))
        return result;
    const names = Object.keys(defaults.modules);
    applyFields(result, local, names);
    result.workspaceDisplay = workspaceSettings(defaults.workspaceDisplay, local.workspaceDisplay);
    if (isObject(local.monitors)) {
        for (const name of Object.keys(local.monitors)) {
            if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/.test(name) || !isObject(local.monitors[name]))
                continue;
            const output = { modules: {} };
            applyFields(output, local.monitors[name], names);
            result.monitors[name] = output;
        }
    }
    return result;
}

function normalWorkspaceEntries(config, workspaces) {
    const ids = [];
    for (let id = 1; id <= config.minimumCount; id++)
        ids.push(id);
    for (const workspace of workspaces) {
        if (Number.isSafeInteger(workspace.id) && workspace.id > 0 && !ids.includes(workspace.id))
            ids.push(workspace.id);
    }
    ids.sort((a, b) => a - b);
    return ids.map(id => ({ id: id, label: config.normalLabels[id] || String(id) }));
}

function specialWorkspaceEntries(config, workspaces) {
    const names = [];
    for (const workspace of workspaces) {
        if (typeof workspace.name !== "string" || !workspace.name.startsWith("special:"))
            continue;
        const name = workspace.name.slice(8);
        if (name !== "" && !names.includes(name))
            names.push(name);
    }
    names.sort();
    return names.map(name => ({
        name: name,
        label: Object.prototype.hasOwnProperty.call(config.specialLabels, name) ? config.specialLabels[name] : name
    }));
}

function screenConfig(config, name) {
    const override = config.monitors[name] || {};
    const modules = Object.assign({}, config.modules, override.modules);
    if (!modules.network) {
        modules.wifiMenu = false;
        modules.vpn = false;
    }
    if (!modules.calendar)
        modules.weather = false;
    return {
        mode: override.mode || config.mode,
        hoverToggleEnabled: override.hoverToggleEnabled === undefined ? config.hoverToggleEnabled : override.hoverToggleEnabled,
        modules: modules
    };
}
