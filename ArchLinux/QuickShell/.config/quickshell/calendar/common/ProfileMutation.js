function failure(field, message) {
    return { ok: false, field, message }
}

const profileKeys = ["id", "name", "color", "type", "visible"]
const profileTypes = new Set(["local", "imported", "synced"])
const idPattern = /^[a-z0-9][a-z0-9_-]*$/
const colorPattern = /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i

function defaultProfiles() {
    return [
        { id: "edt_unistra", name: "University", color: "#7b9acc", type: "imported", visible: true },
        { id: "personal", name: "Personal", color: "#b58bc8", type: "local", visible: true }
    ]
}

function validateProfile(profile) {
    if (!profile || typeof profile !== "object" || Array.isArray(profile)
            || Object.keys(profile).length !== profileKeys.length
            || Object.keys(profile).some(key => !profileKeys.includes(key)))
        return failure("profile", "Profile schema is invalid")
    if (typeof profile.id !== "string" || !idPattern.test(profile.id))
        return failure("id", "Profile ID must use lowercase letters, numbers, _ or -")
    if (typeof profile.name !== "string" || profile.name.trim().length === 0)
        return failure("name", "Profile name is required")
    if (typeof profile.color !== "string" || !colorPattern.test(profile.color))
        return failure("color", "Profile color is invalid")
    if (!profileTypes.has(profile.type))
        return failure("type", "Profile type is invalid")
    if (typeof profile.visible !== "boolean")
        return failure("visible", "Profile visibility is invalid")
    return { ok: true, profile: {
        id: profile.id,
        name: profile.name.trim(),
        color: profile.color,
        type: profile.type,
        visible: profile.visible
    } }
}

function validateProfiles(profiles) {
    if (!Array.isArray(profiles) || profiles.length === 0)
        return failure("profiles", "At least one calendar profile is required")
    const seen = new Set()
    const result = []
    for (const profile of profiles) {
        const validation = validateProfile(profile)
        if (!validation.ok)
            return validation
        if (seen.has(validation.profile.id))
            return failure("id", "Profile IDs must be unique")
        seen.add(validation.profile.id)
        result.push(validation.profile)
    }
    if (!result.some(profile => profile.type === "local" || profile.type === "synced"))
        return failure("profiles", "At least one writable profile is required")
    return { ok: true, profiles: result }
}

function parseRegistry(text) {
    if (typeof text !== "string")
        return failure("storage", "Profile registry is invalid")
    let document
    try {
        document = JSON.parse(text)
    } catch (error) {
        return failure("storage", "Profile registry is malformed")
    }
    if (!document || typeof document !== "object" || Array.isArray(document)
            || Object.keys(document).length !== 2 || document.version !== 1
            || !Array.isArray(document.profiles))
        return failure("storage", "Profile registry schema is unsupported")
    return validateProfiles(document.profiles)
}

function serializeRegistry(profiles) {
    const result = validateProfiles(profiles)
    if (!result.ok)
        return result
    return {
        ok: true,
        profiles: result.profiles,
        text: JSON.stringify({ version: 1, profiles: result.profiles }, null, 2) + "\n"
    }
}

function createProfile(profiles, draft) {
    const current = validateProfiles(profiles)
    if (!current.ok)
        return current
    const candidate = validateProfile(Object.assign({ visible: true }, draft))
    if (!candidate.ok)
        return candidate
    if (current.profiles.some(profile => profile.id === candidate.profile.id))
        return failure("id", "Profile ID already exists")
    const next = current.profiles.concat([candidate.profile])
    return { ok: true, profile: candidate.profile, profiles: next }
}

function validateImportTarget(profiles, id, replacingId) {
    const existing = profiles.find(profile => profile.id === id) || null
    if (replacingId && replacingId !== id)
        return failure("id", "Profile ID cannot change during import replacement")
    if (existing) {
        if (existing.type !== "imported" || replacingId !== id)
            return failure("id", "Profile ID already exists")
        return { ok: true, replacing: true, profile: existing }
    }
    if (replacingId)
        return failure("id", "Profile not found")
    return { ok: true, replacing: false }
}

function updateProfile(profiles, id, changes) {
    const current = validateProfiles(profiles)
    if (!current.ok)
        return current
    const index = current.profiles.findIndex(profile => profile.id === id)
    if (index < 0)
        return failure("id", "Profile not found")
    if (Object.prototype.hasOwnProperty.call(changes || {}, "id") && changes.id !== id)
        return failure("id", "Profile ID cannot change")
    const candidate = validateProfile(Object.assign({}, current.profiles[index], changes, { id }))
    if (!candidate.ok)
        return candidate
    const next = current.profiles.slice()
    next[index] = candidate.profile
    return { ok: true, profile: candidate.profile, profiles: next }
}

function removeProfile(profiles, id) {
    const current = validateProfiles(profiles)
    if (!current.ok)
        return current
    const profile = current.profiles.find(candidate => candidate.id === id)
    if (!profile)
        return failure("id", "Profile not found")
    const writableProfiles = current.profiles.filter(candidate => candidate.type === "local" || candidate.type === "synced")
    if (writableProfiles.length === 1 && (profile.type === "local" || profile.type === "synced"))
        return failure("profiles", "Cannot remove last writable profile")
    return { ok: true, profile, profiles: current.profiles.filter(candidate => candidate.id !== id) }
}

function setVisible(profiles, id, visible) {
    if (typeof visible !== "boolean")
        return failure("visible", "Profile visibility is invalid")
    return updateProfile(profiles, id, { visible })
}

if (typeof module !== "undefined") {
    module.exports = {
        createProfile,
        defaultProfiles,
        parseRegistry,
        removeProfile,
        serializeRegistry,
        setVisible,
        updateProfile,
        validateImportTarget,
        validateProfile
    }
}
