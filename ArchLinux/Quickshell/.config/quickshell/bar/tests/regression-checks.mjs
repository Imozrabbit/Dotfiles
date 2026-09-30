import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

async function source(path) {
    return readFile(join(root, path), "utf8");
}

const gpuStats = await source("services/GpuStats.qml");
const battery = await source("services/Battery.qml");
const brightness = await source("services/Brightness.qml");

const keyboardDiscovery = brightness.match(/id: keyboardDiscovery\s+command: \["sh", "-c", `([\s\S]*?)`\]/);
assert.ok(keyboardDiscovery);
const leds = await mkdtemp(join(root, "tests", "keyboard-leds-"));
try {
    const ignored = join(leds, "capslock");
    const keyboard = join(leds, "thinkpad::kbd_backlight");
    await Promise.all([mkdir(ignored), mkdir(keyboard)]);
    await writeFile(join(ignored, "max_brightness"), "1\n");
    await writeFile(join(keyboard, "max_brightness"), "3\n");
    const command = new Function("return `" + keyboardDiscovery[1] + "`")().replace("/sys/class/leds/*::kbd_backlight", leds + "/*::kbd_backlight");
    const detect = () => {
        const result = spawnSync("sh", ["-c", command], { encoding: "utf8" });
        return [result.status, result.stdout.trim()];
    };
    assert.deepEqual(detect(), [0, "thinkpad::kbd_backlight|3"]);
    await writeFile(join(keyboard, "max_brightness"), "0\n");
    assert.deepEqual(detect(), [1, ""]);
} finally {
    await rm(leds, { recursive: true, force: true });
}

const supplyDiscovery = battery.match(/id: powerSupplyDiscovery\s+command: \["sh", "-c", `([\s\S]*?)`\]/);
assert.ok(supplyDiscovery);
const supplies = await mkdtemp(join(root, "tests", "power-supply-"));
try {
    const presentBattery = join(supplies, "BAT9");
    const absentBattery = join(supplies, "BAT1");
    const mains = join(supplies, "ADP1");
    await Promise.all([mkdir(presentBattery), mkdir(absentBattery), mkdir(mains)]);
    await writeFile(join(presentBattery, "type"), "Battery\n");
    await writeFile(join(presentBattery, "present"), "1\n");
    await writeFile(join(absentBattery, "type"), "Battery\n");
    await writeFile(join(absentBattery, "present"), "0\n");
    await writeFile(join(mains, "type"), "Mains\n");
    await writeFile(join(mains, "online"), "0\n");
    const command = new Function("return `" + supplyDiscovery[1] + "`")().replace("/sys/class/power_supply/*", supplies + "/*");
    const detect = () => {
        const result = spawnSync("sh", ["-c", command], { encoding: "utf8" });
        assert.equal(result.status, 0, result.stderr);
        return result.stdout.trim();
    };
    assert.equal(detect(), `${presentBattery}|${mains}`);
    await rm(presentBattery, { recursive: true });
    assert.equal(detect(), `|${mains}`);
    await rm(mains, { recursive: true });
    assert.equal(detect(), "|");
} finally {
    await rm(supplies, { recursive: true, force: true });
}

const discovery = gpuStats.match(/command: \["sh", "-c", `([\s\S]*?)`\]/);
assert.ok(discovery);
const fixture = await mkdtemp(join(root, "tests", "gpu-discovery-"));
try {
    const intel = join(fixture, "card0", "device");
    const nvidia = join(fixture, "card1", "device");
    const amd = join(fixture, "card2", "device");
    await mkdir(join(amd, "hwmon", "hwmon9"), { recursive: true });
    await mkdir(intel, { recursive: true });
    await mkdir(nvidia, { recursive: true });
    await writeFile(join(intel, "vendor"), "0x8086\n");
    await writeFile(join(nvidia, "vendor"), "0x10de\n");
    await writeFile(join(amd, "vendor"), "0x1002\n");
    await writeFile(join(amd, "gpu_busy_percent"), "12\n");
    await writeFile(join(amd, "hwmon", "hwmon9", "name"), "amdgpu\n");

    const command = new Function("return `" + discovery[1] + "`")().replace("/sys/class/drm/card[0-9]*/device", fixture + "/card[0-9]*/device");
    const detect = () => {
        const result = spawnSync("sh", ["-c", command], { encoding: "utf8" });
        assert.equal(result.status, 0, result.stderr);
        return result.stdout.trim();
    };
    assert.equal(detect(), `AMD|${amd}|${join(amd, "hwmon", "hwmon9")}`);
    await rm(join(amd, "hwmon"), { recursive: true });
    assert.equal(detect(), `AMD|${amd}|`);
    await rm(join(fixture, "card2"), { recursive: true });
    assert.equal(detect(), "Intel||");
    await rm(join(fixture, "card0"), { recursive: true });
    assert.equal(detect(), "NVIDIA||");
    await rm(join(fixture, "card1"), { recursive: true });
    assert.equal(detect(), "||");
} finally {
    await rm(fixture, { recursive: true, force: true });
}
console.log("hardware discovery checks passed");
