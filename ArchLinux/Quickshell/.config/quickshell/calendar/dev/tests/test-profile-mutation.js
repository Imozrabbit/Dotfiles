const assert = require("node:assert/strict")
const ProfileMutation = require("../../common/ProfileMutation.js")

const profiles = ProfileMutation.defaultProfiles()
assert.equal(profiles.length, 2)
assert.equal(ProfileMutation.validateProfile({
    id: "personal_sync", name: "Personal Sync", color: "#112233", type: "synced", visible: true
}).ok, true)
assert.equal(ProfileMutation.parseRegistry(
    JSON.stringify({ version: 1, profiles })).ok, true)

for (const text of ["{", "[]", '{"version":2,"profiles":[]}',
    JSON.stringify({ version: 1, profiles: [{ id: "Bad", name: "Bad", color: "#ffffff", type: "local", visible: true }] })])
    assert.equal(ProfileMutation.parseRegistry(text).ok, false)

{
    const result = ProfileMutation.createProfile(profiles, {
        id: "work", name: "Work", color: "#6688aa", type: "local"
    })
    assert.equal(result.ok, true)
    assert.equal(result.profile.visible, true)
    assert.equal(result.profiles.length, 3)
}

assert.equal(ProfileMutation.createProfile(profiles, {
    id: "personal", name: "Other", color: "#6688aa", type: "local"
}).ok, false)
assert.equal(ProfileMutation.updateProfile(profiles, "personal", { id: "work" }).ok, false)

assert.equal(typeof ProfileMutation.validateImportTarget, "function")
assert.equal(ProfileMutation.validateImportTarget(profiles, "personal", "").ok, false)
assert.equal(ProfileMutation.validateImportTarget(profiles, "personal", "personal").ok, false)
assert.equal(ProfileMutation.validateImportTarget(profiles, "edt_unistra", "").ok, false)
assert.equal(ProfileMutation.validateImportTarget(profiles, "edt_unistra", "edt_unistra").replacing, true)
assert.equal(ProfileMutation.validateImportTarget(profiles, "new_feed", "").replacing, false)
assert.equal(ProfileMutation.validateImportTarget(profiles, "new_feed", "personal").ok, false)

{
    const result = ProfileMutation.setVisible(profiles, "personal", false)
    assert.equal(result.ok, true)
    assert.equal(result.profile.visible, false)
}

assert.equal(ProfileMutation.removeProfile(profiles, "edt_unistra").ok, true)
assert.equal(ProfileMutation.removeProfile(profiles, "personal").ok, false)
assert.equal(ProfileMutation.removeProfile([
    { id: "personal", name: "Personal", color: "#b58bc8", type: "local", visible: true },
    { id: "remote", name: "Remote", color: "#6688aa", type: "synced", visible: true }
], "personal").ok, true)
assert.equal(ProfileMutation.removeProfile([{ id: "personal", name: "Personal", color: "#b58bc8", type: "local", visible: true }], "personal").ok, false)
assert.equal(ProfileMutation.serializeRegistry(profiles).text.endsWith("\n"), true)
console.log("Profile mutation tests passed")
