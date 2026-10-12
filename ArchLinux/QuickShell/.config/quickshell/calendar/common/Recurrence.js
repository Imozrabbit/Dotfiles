function failure(field, message) {
    return { ok: false, field, message }
}

function exactKeys(value, keys) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
        && Object.keys(value).length === keys.length
        && keys.every(key => Object.prototype.hasOwnProperty.call(value, key))
}

function integerInRange(value, minimum, maximum) {
    return Number.isSafeInteger(value) && value >= minimum && value <= maximum
}

function validDate(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value))
        return false
    const year = Number(value.slice(0, 4))
    const month = Number(value.slice(5, 7))
    const day = Number(value.slice(8, 10))
    if (year < 1)
        return false
    // Calendar dates must not depend on the viewing host's timezone/DST.
    const date = new Date(0)
    date.setUTCFullYear(year, month - 1, day)
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1
        && date.getUTCDate() === day
}

function sortedUnique(values, compare) {
    const sorted = values.slice().sort(compare)
    return sorted.filter((value, index) => index === 0 || compare(value, sorted[index - 1]) !== 0)
}

function canonicalRule(value) {
    if (!exactKeys(value, ["frequency", "interval", "startsOn", "pattern", "ends"]))
        return failure("recurrence", "Recurrence schema is invalid")
    if (!["daily", "weekly", "monthly", "yearly"].includes(value.frequency))
        return failure("frequency", "Choose a supported repeat frequency")
    if (!integerInRange(value.interval, 1, 2147483647))
        return failure("interval", "Repeat interval must be a positive whole number up to 2147483647")
    if (!validDate(value.startsOn))
        return failure("startsOn", "Enter a valid repeat start date")

    const source = value.pattern
    let pattern
    let startsOn = value.startsOn
    const patternFailure = () => failure("pattern", "Choose valid repeat days for this frequency")
    const numbers = (a, b) => a - b
    switch (value.frequency) {
    case "daily":
        if (!exactKeys(source, []))
            return patternFailure()
        pattern = {}
        break
    case "weekly":
        if (!exactKeys(source, ["weekdays"]) || !Array.isArray(source.weekdays)
                || source.weekdays.length === 0)
            return patternFailure()
        for (const weekday of source.weekdays) {
            if (!integerInRange(weekday, 0, 6))
                return patternFailure()
        }
        pattern = { weekdays: sortedUnique(source.weekdays, numbers) }
        break
    case "monthly":
        startsOn = startsOn.slice(0, 7) + "-01"
        if (exactKeys(source, ["mode", "days"]) && source.mode === "dates"
                && Array.isArray(source.days) && source.days.length > 0) {
            for (const day of source.days) {
                if (!integerInRange(day, 1, 31))
                    return patternFailure()
            }
            pattern = { mode: "dates", days: sortedUnique(source.days, numbers) }
        } else if (exactKeys(source, ["mode", "positions"]) && source.mode === "positions"
                && Array.isArray(source.positions) && source.positions.length > 0) {
            const positions = []
            for (const position of source.positions) {
                if (!exactKeys(position, ["ordinal", "weekday"])
                        || !(position.ordinal === -1 || integerInRange(position.ordinal, 1, 5))
                        || !integerInRange(position.weekday, 0, 6))
                    return patternFailure()
                positions.push({ ordinal: position.ordinal, weekday: position.weekday })
            }
            pattern = { mode: "positions", positions: sortedUnique(positions,
                (a, b) => a.ordinal - b.ordinal || a.weekday - b.weekday) }
        } else {
            return patternFailure()
        }
        break
    case "yearly": {
        startsOn = startsOn.slice(0, 4) + "-01-01"
        if (!exactKeys(source, ["dates"]) || !Array.isArray(source.dates) || source.dates.length === 0)
            return patternFailure()
        const dates = []
        // Leap-year ceiling accepts February 29 even when the boundary year is not leap.
        const monthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        for (const date of source.dates) {
            if (!exactKeys(date, ["month", "day"]) || !integerInRange(date.month, 1, 12)
                    || !integerInRange(date.day, 1, monthDays[date.month - 1]))
                return patternFailure()
            dates.push({ month: date.month, day: date.day })
        }
        pattern = { dates: sortedUnique(dates, (a, b) => a.month - b.month || a.day - b.day) }
        break
    }
    }

    const sourceEnds = value.ends
    let ends
    if (exactKeys(sourceEnds, ["mode"]) && sourceEnds.mode === "never") {
        ends = { mode: "never" }
    } else if (exactKeys(sourceEnds, ["mode", "date"]) && sourceEnds.mode === "date"
            && validDate(sourceEnds.date) && sourceEnds.date >= startsOn) {
        ends = { mode: "date", date: sourceEnds.date }
    } else if (exactKeys(sourceEnds, ["mode", "count"]) && sourceEnds.mode === "count"
            && integerInRange(sourceEnds.count, 1, 2147483647)) {
        ends = { mode: "count", count: sourceEnds.count }
    } else {
        return failure("ends", "Choose never, an end date on or after repeat start, or a positive whole count up to 2147483647")
    }

    return { ok: true, rule: {
        frequency: value.frequency,
        interval: value.interval,
        startsOn,
        pattern,
        ends
    } }
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { canonicalRule }
