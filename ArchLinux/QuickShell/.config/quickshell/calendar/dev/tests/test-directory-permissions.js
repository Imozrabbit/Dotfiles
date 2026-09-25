const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const workspace = fs.mkdtempSync(path.join(__dirname, ".directory-check-"))
const calendarDirectory = path.join(workspace, "calendars")
try {
    execFileSync("install", ["-d", "-m", "700", "--", calendarDirectory])
    assert.equal(fs.statSync(calendarDirectory).mode & 0o777, 0o700)
    fs.chmodSync(calendarDirectory, 0o755)
    execFileSync("install", ["-d", "-m", "700", "--", calendarDirectory])
    assert.equal(fs.statSync(calendarDirectory).mode & 0o777, 0o700)
} finally {
    fs.rmSync(workspace, { recursive: true })
}

console.log("Calendar directory permissions tests passed")
