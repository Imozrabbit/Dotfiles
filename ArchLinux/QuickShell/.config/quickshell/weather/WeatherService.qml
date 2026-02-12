pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: svc

    // Strasbourg (adjust if you want)
    property real lat: 48.5734
    property real lon: 7.7521
    property string city: "Strasbourg"

    // Refresh every 15 min
    property int refreshMs: 15 * 60 * 1000

    // State the UI reads
    property bool ok: false
    property string error: ""
    property date lastUpdated: new Date(0)

    // Current
    property real nowTempC: NaN
    property int nowCode: -1

    // 3-day forecast (today + next 2)
    property var tmaxC: []       // [..]
    property var tminC: []       // [..]
    property var codes: []       // [..]

    // Minimal weathercode -> (icon, text)
    function decode(code) {
        if (code === 0)
            return {
                i: " ",
                t: "Clear"
            };
        if (code === 1)
            return {
                i: " ",
                t: "Mainly clear"
            };
        if (code === 2)
            return {
                i: " ",
                t: "Partly cloudy"
            };
        if (code === 3)
            return {
                i: "󰖐 ",
                t: "Overcast"
            };
        if (code === 45 || code === 48)
            return {
                i: "󰖑 ",
                t: "Fog"
            };
        if (code >= 51 && code <= 57)
            return {
                i: " ",
                t: "Drizzle"
            };
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82))
            return {
                i: " ",
                t: "Rain"
            };
        if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86))
            return {
                i: " ",
                t: "Snow"
            };
        if (code >= 95 && code <= 99)
            return {
                i: " ",
                t: "Thunderstorm"
            };
        return {
            i: "",
            t: "Unknown"
        };
    }

    function url() {
        // Open-Meteo Forecast API:
        // - current_weather=true for "now"
        // - daily=weathercode,temp max/min
        // - forecast_days=1 for today, change this number if need more forecast
        // Docs: https://open-meteo.com/en/docs
        return "https://api.open-meteo.com/v1/forecast" + "?latitude=" + lat + "&longitude=" + lon + "&current_weather=true" + "&daily=weathercode,temperature_2m_max,temperature_2m_min" + "&forecast_days=1" + "&timezone=auto";
    }

    function refresh() {
        proc.command = ["sh", "-c", "curl -fsSL '" + url() + "'"];
        proc.running = true;
    }

    Timer {
        interval: svc.refreshMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: svc.refresh()
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);

                    svc.nowTempC = o.current_weather?.temperature ?? NaN;
                    svc.nowCode = o.current_weather?.weathercode ?? -1;

                    const d = o.daily;
                    svc.tmaxC = d?.temperature_2m_max ?? [];
                    svc.tminC = d?.temperature_2m_min ?? [];
                    svc.codes = d?.weathercode ?? [];

                    svc.ok = true;
                    svc.error = "";
                    svc.lastUpdated = new Date();
                } catch (_) {
                    svc.ok = false;
                    svc.error = "parse error";
                }
            }
        }
    }
}
