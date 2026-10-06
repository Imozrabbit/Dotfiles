function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function applyFields(target, override, moduleNames) {
    if (!isObject(override))
        return;
    if (override.mode === "off" || override.mode === "always" || override.mode === "hover")
        target.mode = override.mode;
    if (["off", "always", "hover"].includes(override.topMediaMode))
        target.topMediaMode = override.topMediaMode;
    if (typeof override.hoverToggleEnabled === "boolean")
        target.hoverToggleEnabled = override.hoverToggleEnabled;
    if (typeof override.edgeSpacing === "number" && isFinite(override.edgeSpacing) && override.edgeSpacing >= 0 && override.edgeSpacing <= 100)
        target.edgeSpacing = override.edgeSpacing;
    if (Array.isArray(override.launchers))
        target.launchers = launcherEntries(override.launchers);
    if (isObject(override.mouseBattery) && typeof override.mouseBattery.name === "string"
        && override.mouseBattery.name.trim() !== "" && override.mouseBattery.name.length <= 128)
        target.mouseBattery = { name: override.mouseBattery.name.trim() };
    if (isObject(override.modules)) {
        for (const name of moduleNames) {
            if (typeof override.modules[name] === "boolean")
                target.modules[name] = override.modules[name];
        }
    }
}

function launcherEntries(entries) {
    const validCommand = command => command === undefined || Array.isArray(command)
        && command.every(argument => typeof argument === "string" && !argument.includes("\0"))
        && (command.length === 0 || command[0].trim() !== "");
    return entries.filter(entry => isObject(entry) && typeof entry.icon === "string" && entry.icon.trim() !== ""
        && validCommand(entry.leftCommand) && validCommand(entry.rightCommand)).map(entry => ({
        icon: entry.icon.trim(),
        tooltip: typeof entry.tooltip === "string" ? entry.tooltip : "",
        leftCommand: entry.leftCommand || [],
        rightCommand: entry.rightCommand || []
    }));
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

function resolveConfig(defaults, text, previous) {
    const result = {
        mode: defaults.mode,
        topMediaMode: defaults.topMediaMode || "hover",
        edgeSpacing: defaults.edgeSpacing,
        hoverToggleEnabled: defaults.hoverToggleEnabled,
        launchers: launcherEntries(defaults.launchers || []),
        mouseBattery: Object.assign({}, defaults.mouseBattery),
        vpn: { routerManagedSsids: (defaults.vpn?.routerManagedSsids || []).slice() },
        protonManager: Object.assign({}, defaults.protonManager || {}),
        modules: Object.assign({}, defaults.modules),
        workspaceDisplay: workspaceSettings(defaults.workspaceDisplay, null),
        monitors: {}
    };
    let local;
    try {
        local = JSON.parse(text);
    } catch (_) {
        return previous || result;
    }
    if (!isObject(local))
        return previous || result;
    const names = Object.keys(defaults.modules);
    applyFields(result, local, names);
    if (isObject(local.protonManager)) {
        for (const key of ["compatibilityToolsDir", "umuConfigPath", "sandboxCompatibilityToolsDir"]) {
            const value = local.protonManager[key];
            if (typeof value === "string" && value.length <= 4096 && value.startsWith("/")
                && value !== "/" && !value.includes("\0") && !value.split("/").includes(".."))
                result.protonManager[key] = value;
        }
    }
    if (isObject(local.vpn) && Array.isArray(local.vpn.routerManagedSsids))
        result.vpn.routerManagedSsids = local.vpn.routerManagedSsids.filter((ssid, index, entries) =>
            typeof ssid === "string" && ssid !== "" && ssid.length <= 32 && !ssid.includes("\0") && entries.indexOf(ssid) === index);
    result.workspaceDisplay = workspaceSettings(defaults.workspaceDisplay, local.workspaceDisplay);
    if (isObject(local.monitors)) {
        for (const name of Object.keys(local.monitors)) {
            if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/.test(name) || !isObject(local.monitors[name]))
                continue;
            const output = { modules: {} };
            applyFields(output, local.monitors[name], names);
            if (isObject(local.monitors[name].workspaceDisplay))
                output.workspaceDisplay = local.monitors[name].workspaceDisplay;
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

function specialWorkspaceEntries(config, workspaces, monitors, focusedMonitor) {
    const names = [];
    const occupiedNames = [];
    for (const workspace of workspaces) {
        if (typeof workspace.name !== "string" || !workspace.name.startsWith("special:"))
            continue;
        const name = workspace.name.slice(8);
        if (name !== "" && !names.includes(name))
            names.push(name);
        if ((workspace.toplevels?.values.length ?? 0) > 0 && !occupiedNames.includes(name))
            occupiedNames.push(name);
    }
    const focusedName = focusedMonitor?.lastIpcObject?.specialWorkspace?.name ?? "";
    const openedNames = (monitors || []).map(monitor => monitor.lastIpcObject?.specialWorkspace?.name ?? "");
    if (focusedName !== "")
        openedNames.push(focusedName);
    for (const fullName of openedNames) {
        if (fullName.startsWith("special:") && fullName.length > 8 && !names.includes(fullName.slice(8)))
            names.push(fullName.slice(8));
    }
    names.sort();
    return names.filter(name => occupiedNames.includes(name) || openedNames.includes("special:" + name)).map(name => ({
        name: name,
        label: Object.prototype.hasOwnProperty.call(config.specialLabels, name) ? config.specialLabels[name] : name,
        state: focusedName === "special:" + name ? "focused" : occupiedNames.includes(name) ? "occupied" : "empty"
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
        topMediaMode: override.topMediaMode || config.topMediaMode,
        edgeSpacing: override.edgeSpacing === undefined ? config.edgeSpacing : override.edgeSpacing,
        hoverToggleEnabled: override.hoverToggleEnabled === undefined ? config.hoverToggleEnabled : override.hoverToggleEnabled,
        launchers: override.launchers === undefined ? config.launchers : override.launchers,
        mouseBattery: override.mouseBattery || config.mouseBattery,
        workspaceDisplay: workspaceSettings(config.workspaceDisplay, override.workspaceDisplay),
        modules: modules
    };
}
