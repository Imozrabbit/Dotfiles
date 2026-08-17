import QtQuick
import Quickshell.Io

Item {
    id: hw

    // -------------------- Turbostat effective CPU clock feed and CPU wattage -------------------- //
    property real effMHz: 0
    property real effValue: 0
    property string effText: "0"
    property real maxMHz: 4700
    property var effSamples: []
    property int effMaxSamples: 80
    property real cpuPkgWatt: 0
    property string cpuPkgWattText: "0W"
    Process {
        id: tsProc
        command: ["sudo", "-n", "turbostat", "--no-msr", "--Summary", "--quiet", "--show", "Bzy_MHz,PkgWatt", "--interval", "1", "--num_iterations", "1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var mhz = NaN;
                var watt = NaN;

                for (var li = lines.length - 1; li >= 0; --li) {
                    var line = lines[li].trim();
                    if (!line.length)
                        continue;

                    var m = line.match(/^([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)$/);
                    if (m) {
                        mhz = Number(m[1]);
                        watt = Number(m[2]);
                        break;
                    }
                }

                if (isNaN(mhz) || isNaN(watt))
                    return;

                hw.effMHz = mhz;
                var raw = mhz / hw.maxMHz;
                raw = Math.max(0, Math.min(1, raw));
                hw.effValue = 0.85 * hw.effValue + 0.15 * raw;
                hw.effText = Math.round(mhz).toString();

                hw.cpuPkgWatt = watt;
                hw.cpuPkgWattText = Math.round(watt) + "W";

                var samples = hw.effSamples.slice();
                samples.push(hw.effValue);
                if (samples.length > hw.effMaxSamples)
                    samples.splice(0, samples.length - hw.effMaxSamples);
                hw.effSamples = samples;
            }
        }
    }

    // --------------------             CPU temp (Tccd1 = temp3)             -------------------- //
    property real cpuTempC: 0
    property string tccd1Path: "/sys/class/hwmon/hwmon4/temp3_input"

    Process {
        id: tempProc
        command: ["cat", hw.tccd1Path]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mC = Number(this.text.trim());
                if (!isNaN(mC))
                    hw.cpuTempC = mC / 1000.0;
            }
        }
    }

    // --------------------          CPU usage from /proc/stat        -------------------- //
    property real cpuUsage01: 0
    property string cpuUsageText: "0%"
    property var _prevStat: null // [total, idle]

    Process {
        id: statProc
        command: ["cat", "/proc/stat"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                if (lines.length === 0)
                    return;

                var parts = lines[0].trim().split(/\s+/);
                if (parts[0] !== "cpu")
                    return;

                var v = [];
                for (var i = 1; i < parts.length; i++) {
                    var n = Number(parts[i]);
                    if (!isNaN(n))
                        v.push(n);
                }
                if (v.length < 4)
                    return;

                var idle = v[3];
                var iowait = (v.length > 4) ? v[4] : 0;

                var total = 0;
                for (var k = 0; k < v.length; k++)
                    total += v[k];

                var idleAll = idle + iowait;

                if (hw._prevStat !== null) {
                    var totald = total - hw._prevStat[0];
                    var idled = idleAll - hw._prevStat[1];
                    if (totald > 0) {
                        var usage = 1.0 - (idled / totald);
                        usage = Math.max(0, Math.min(1, usage));
                        hw.cpuUsage01 = usage;
                        hw.cpuUsageText = Math.round(usage * 100) + "%";
                    }
                }

                hw._prevStat = [total, idleAll];
            }
        }
    }

    // --------------------             GPU clockspeed              -------------------- //
    property string gpuSclkPath: "/sys/class/drm/card1/device/pp_dpm_sclk"
    property real gpuSclkMHz: 0
    property real gpuSclkValue: 0 // From 0 to 1
    property string gpuSclkText: "0"
    property real gpuSclkMaxMHz: 3300
    // -------------------- GPU SCLK graph samples -------------------- //
    property var gpuSclkSamples: []
    property int gpuSclkMaxSamples: 80
    property string gpuSclkHzPath: "/sys/class/drm/card1/device/hwmon/hwmon3/freq1_input"
    Process {
        id: gpuSclkProc
        command: ["cat", hw.gpuSclkPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var cur = NaN;
                var max = 0;
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    // examples: "7: 2475Mhz *"  or "2: 800Mhz"
                    var m = line.match(/:\s*([0-9]+)\s*Mhz/i);
                    if (!m)
                        continue;
                    var mhz = Number(m[1]);
                    if (!isNaN(mhz)) {
                        if (mhz > max)
                            max = mhz;
                        if (line.indexOf("*") !== -1)
                            cur = mhz;
                    }
                }
                // fallback: if no '*' found, just use max
                if (isNaN(cur))
                    cur = max;
                if (!max || isNaN(cur))
                    return;
                hw.gpuSclkMHz = cur;
                hw.gpuSclkMaxMHz = max;
                var raw = cur / max;
                raw = Math.max(0, Math.min(1, raw));
                // optional smoothing like CPU (keeps it visually stable)
                hw.gpuSclkValue = 0.85 * hw.gpuSclkValue + 0.15 * raw;
                hw.gpuSclkText = Math.round(cur).toString();
                // push into graph history (same pattern as CPU effSamples)
                var s = hw.gpuSclkSamples.slice();
                s.push(hw.gpuSclkValue);
                if (s.length > hw.gpuSclkMaxSamples)
                    s.splice(0, s.length - hw.gpuSclkMaxSamples);
                hw.gpuSclkSamples = s;
            }
        }
    }

    // --------------------             GPU temperature             -------------------- //
    property string gpuTempPath: "/sys/class/drm/card1/device/hwmon/hwmon3/temp2_input"
    property real gpuTempC: 0
    Process {
        id: gpuTempProc
        command: ["cat", hw.gpuTempPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mC = Number(this.text.trim());
                if (!isNaN(mC))
                    hw.gpuTempC = mC / 1000.0;
            }
        }
    }

    // -------------------------             GPU Vram             -------------------------//
    property real gpuVramUsage01: 0
    property string gpuVramUsedPath: "/sys/class/drm/card1/device/mem_info_vram_used"
    property string gpuVramTotalPath: "/sys/class/drm/card1/device/mem_info_vram_total"
    property real _gpuVramUsedBytes: 0
    property real _gpuVramTotalBytes: 0
    property string gpuMclkHzPath: "/sys/class/drm/card1/device/hwmon/hwmon3/freq2_input"
    property real gpuMclkMHz: 0
    property string gpuMclkText: "0"
    function _updateGpuVramUsage() {
        if (hw._gpuVramTotalBytes > 0) {
            var u = hw._gpuVramUsedBytes / hw._gpuVramTotalBytes;
            hw.gpuVramUsage01 = Math.max(0, Math.min(1, u));
        }
    }
    Process {
        id: gpuVramUsedProc
        command: ["cat", hw.gpuVramUsedPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var b = Number(this.text.trim());
                if (!isNaN(b)) {
                    hw._gpuVramUsedBytes = b;
                    hw._updateGpuVramUsage();
                }
            }
        }
    }
    Process {
        id: gpuVramTotalProc
        command: ["cat", hw.gpuVramTotalPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var b = Number(this.text.trim());
                if (!isNaN(b)) {
                    hw._gpuVramTotalBytes = b;
                    hw._updateGpuVramUsage();
                }
            }
        }
    }
    Process {
        id: gpuMclkProc
        command: ["cat", hw.gpuMclkHzPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var hz = Number(this.text.trim());
                if (isNaN(hz))
                    return;
                var mhz = hz / 1000000.0;
                hw.gpuMclkMHz = mhz;
                var ghz = 2 * mhz / 1000.0;
                hw.gpuMclkText = ghz.toFixed(2);
            }
        }
    }

    // -------------------------             GPU Usage             -------------------------//
    property string gpuBusyPath: "/sys/class/drm/card1/device/gpu_busy_percent"
    property real gpuUsage01: 0
    property string gpuUsageText: "0"
    Process {
        id: gpuBusyProc
        command: ["cat", hw.gpuBusyPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = Number(this.text.trim()); // 0..100
                if (isNaN(p))
                    return;
                p = Math.max(0, Math.min(100, p));
                hw.gpuUsage01 = p / 100.0;
                hw.gpuUsageText = Math.round(p).toString();
            }
        }
    }

    // -------------------------             GPU Voltage             -------------------------//
    property string gpuVoltPath: "/sys/class/drm/card1/device/hwmon/hwmon3/in0_input"
    property string gpuVoltText: "0.00"
    Process {
        id: gpuVoltProc
        command: ["cat", hw.gpuVoltPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mv = Number(this.text.trim()); // mV
                if (isNaN(mv))
                    return;
                hw.gpuVoltText = (mv / 1000.0).toFixed(1);
            }
        }
    }

    // -------------------------             GPU Voltage             -------------------------//
    property string gpuPowerPath: "/sys/class/drm/card1/device/hwmon/hwmon3/power1_average"
    property real gpuPowerW: 0
    Process {
        id: gpuPowerProc
        command: ["cat", hw.gpuPowerPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var uw = Number(this.text.trim()); // µW
                if (isNaN(uw))
                    return;
                var w = uw / 1000000.0;
                hw.gpuPowerW = w;
            }
        }
    }

    Timer {
        id: poll
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            tsProc.running = true;
            tempProc.running = true;
            statProc.running = true;
            gpuSclkProc.running = true;
            gpuTempProc.running = true;
            gpuVramUsedProc.running = true;
            gpuVramTotalProc.running = true;
            gpuMclkProc.running = true;
            gpuBusyProc.running = true;
            gpuVoltProc.running = true;
            gpuPowerProc.running = true;
        }
    }
}
