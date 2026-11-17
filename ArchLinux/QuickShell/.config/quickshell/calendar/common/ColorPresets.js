function normalizeColor(value) {
    if (typeof value !== "string" || !/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(value))
        return ""
    const color = value.toLowerCase()
    return color.length === 9 && color.slice(1, 3) === "ff" ? "#" + color.slice(3) : color
}

function normalizeColors(values) {
    if (!Array.isArray(values))
        return null
    const colors = []
    for (const value of values) {
        const color = normalizeColor(value)
        if (!color)
            return null
        if (!colors.includes(color))
            colors.push(color)
    }
    return colors
}

function seed(profiles) {
    return normalizeColors(profiles.map(profile => profile.color)) || []
}

function parse(text) {
    let document
    try {
        document = JSON.parse(text)
    } catch (error) {
        return { ok: false, message: "Color preset file is malformed" }
    }
    if (!document || Array.isArray(document) || Object.keys(document).length !== 2 || document.version !== 1)
        return { ok: false, message: "Color preset file schema is unsupported" }
    const colors = normalizeColors(document.colors)
    return colors ? { ok: true, colors } : { ok: false, message: "Color preset file contains invalid colors" }
}

if (typeof module !== "undefined")
    module.exports = { normalizeColor, normalizeColors, seed, parse }
