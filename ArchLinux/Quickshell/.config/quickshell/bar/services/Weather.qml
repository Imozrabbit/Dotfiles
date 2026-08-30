import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var locations: []
    property string activeLocationKey: ""
    property var searchResults: []
    property string searchError: ""
    property var searchRequest: null
    property var currentWeather: null
    property var hourlyForecast: []
    property var dailyForecast: []
    property string forecastLocationKey: ""
    property double fetchedAt: 0
    property string forecastError: ""
    property var forecastRequest: null
    readonly property bool searching: root.searchRequest !== null
    readonly property bool loading: root.forecastRequest !== null
    readonly property bool hasForecast: root.currentWeather !== null && root.forecastLocationKey === root.activeLocationKey

    function numberValue(value) {
        return value === null || value === undefined || value === "" ? NaN : Number(value);
    }

    function normalizeLocation(value) {
        if (!value || typeof value.name !== "string" || value.name.trim() === "")
            return null;

        const latitude = root.numberValue(value.latitude);
        const longitude = root.numberValue(value.longitude);
        if (!isFinite(latitude) || latitude < -90 || latitude > 90 || !isFinite(longitude) || longitude < -180 || longitude > 180)
            return null;

        return {
            key: latitude.toFixed(6) + "," + longitude.toFixed(6),
            name: value.name.trim(),
            region: typeof value.admin1 === "string" ? value.admin1.trim() : typeof value.region === "string" ? value.region.trim() : "",
            country: typeof value.country === "string" ? value.country.trim() : "",
            latitude: latitude,
            longitude: longitude
        };
    }

    function saveState() {
        stateFile.setText(JSON.stringify({
            locations: root.locations,
            activeLocation: root.activeLocationKey || null,
            forecast: root.hasForecast ? {
                locationKey: root.forecastLocationKey,
                fetchedAt: root.fetchedAt,
                current: root.currentWeather,
                hourly: root.hourlyForecast,
                daily: root.dailyForecast
            } : null
        }));
    }

    function isNumber(value) {
        return typeof value === "number" && isFinite(value);
    }

    function validForecast(forecast) {
        if (!forecast || typeof forecast.locationKey !== "string" || !root.isNumber(forecast.fetchedAt) || !forecast.current || !Array.isArray(forecast.hourly) || !Array.isArray(forecast.daily))
            return false;

        const current = forecast.current;
        if (![current.code, current.temperature, current.apparentTemperature, current.windSpeed, current.precipitation, current.high, current.low, current.isDay].every(value => root.isNumber(value)))
            return false;

        return forecast.hourly.length === 6 && forecast.hourly.every(hour => typeof hour.time === "string" && [hour.code, hour.temperature, hour.precipitationChance, hour.isDay].every(value => root.isNumber(value))) && forecast.daily.length === 3 && forecast.daily.every(day => typeof day.date === "string" && [day.code, day.high, day.low, day.precipitationChance].every(value => root.isNumber(value)));
    }

    function applyForecast(forecast) {
        root.forecastLocationKey = forecast.locationKey;
        root.fetchedAt = forecast.fetchedAt;
        root.currentWeather = forecast.current;
        root.hourlyForecast = forecast.hourly;
        root.dailyForecast = forecast.daily;
    }

    function clearForecast() {
        root.forecastLocationKey = "";
        root.fetchedAt = 0;
        root.currentWeather = null;
        root.hourlyForecast = [];
        root.dailyForecast = [];
        root.forecastError = "";
    }

    function loadState(text) {
        try {
            const data = JSON.parse(text);
            if (!data || !Array.isArray(data.locations))
                throw new Error("Invalid weather state");

            const locations = [];
            for (const entry of data.locations) {
                const location = root.normalizeLocation(entry);
                if (location && !locations.some(existing => existing.key === location.key))
                    locations.push(location);
            }

            root.locations = locations;
            root.activeLocationKey = locations.some(location => location.key === data.activeLocation) ? data.activeLocation : "";
            if (root.validForecast(data.forecast) && data.forecast.locationKey === root.activeLocationKey)
                root.applyForecast(data.forecast);
            else
                root.clearForecast();
        } catch (error) {
            root.locations = [];
            root.activeLocationKey = "";
            root.clearForecast();
            root.saveState();
        }
    }

    function parseForecast(data, locationKey) {
        const current = data ? data.current : null;
        const hourly = data ? data.hourly : null;
        const daily = data ? data.daily : null;
        if (!current || !hourly || !daily || typeof current.time !== "string" || !Array.isArray(hourly.time) || !Array.isArray(daily.time))
            return null;

        const currentWeather = {
            code: root.numberValue(current.weather_code),
            temperature: root.numberValue(current.temperature_2m),
            apparentTemperature: root.numberValue(current.apparent_temperature),
            windSpeed: root.numberValue(current.wind_speed_10m),
            precipitation: root.numberValue(current.precipitation),
            high: root.numberValue(daily.temperature_2m_max ? daily.temperature_2m_max[0] : null),
            low: root.numberValue(daily.temperature_2m_min ? daily.temperature_2m_min[0] : null),
            isDay: root.numberValue(current.is_day)
        };

        const firstHour = hourly.time.findIndex(time => typeof time === "string" && time >= current.time);
        const hours = [];
        for (let index = firstHour; index >= 0 && index < firstHour + 6; index++) {
            hours.push({
                time: typeof hourly.time[index] === "string" ? hourly.time[index].slice(11, 16) : "",
                code: root.numberValue(hourly.weather_code ? hourly.weather_code[index] : null),
                temperature: root.numberValue(hourly.temperature_2m ? hourly.temperature_2m[index] : null),
                precipitationChance: root.numberValue(hourly.precipitation_probability ? hourly.precipitation_probability[index] : null),
                isDay: root.numberValue(hourly.is_day ? hourly.is_day[index] : null)
            });
        }

        const days = [];
        for (let index = 1; index <= 3; index++) {
            days.push({
                date: daily.time[index],
                code: root.numberValue(daily.weather_code ? daily.weather_code[index] : null),
                high: root.numberValue(daily.temperature_2m_max ? daily.temperature_2m_max[index] : null),
                low: root.numberValue(daily.temperature_2m_min ? daily.temperature_2m_min[index] : null),
                precipitationChance: root.numberValue(daily.precipitation_probability_max ? daily.precipitation_probability_max[index] : null)
            });
        }

        const forecast = {
            locationKey: locationKey,
            fetchedAt: Date.now(),
            current: currentWeather,
            hourly: hours,
            daily: days
        };
        return root.validForecast(forecast) ? forecast : null;
    }

    function activeLocation() {
        return root.locations.find(location => location.key === root.activeLocationKey);
    }

    function refreshIfStale() {
        if (root.activeLocationKey === "" || root.loading || root.hasForecast && Date.now() - root.fetchedAt < 900000)
            return;
        root.refreshForecast();
    }

    function refreshForecast() {
        const location = root.activeLocation();
        if (!location)
            return;

        if (root.forecastRequest)
            root.forecastRequest.abort();

        root.forecastError = "";
        const request = new XMLHttpRequest();
        const locationKey = location.key;
        root.forecastRequest = request;
        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE || root.forecastRequest !== request)
                return;

            root.forecastRequest = null;
            if (request.status !== 200) {
                root.forecastError = "Weather refresh failed";
                return;
            }

            try {
                const forecast = root.parseForecast(JSON.parse(request.responseText), locationKey);
                if (!forecast) {
                    root.forecastError = "Invalid weather response";
                    return;
                }
                if (root.activeLocationKey !== locationKey)
                    return;
                root.applyForecast(forecast);
                root.saveState();
            } catch (error) {
                root.forecastError = "Invalid weather response";
            }
        };

        const parameters = "latitude=" + location.latitude + "&longitude=" + location.longitude + "&current=temperature_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,precipitation&hourly=temperature_2m,precipitation_probability,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm&timezone=auto&forecast_days=4";
        request.open("GET", "https://api.open-meteo.com/v1/forecast?" + parameters);
        request.send();
    }

    function search(query) {
        const name = query.trim();
        if (name === "")
            return;

        if (root.searchRequest)
            root.searchRequest.abort();

        root.searchError = "";
        root.searchResults = [];

        const request = new XMLHttpRequest();
        root.searchRequest = request;
        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE || root.searchRequest !== request)
                return;

            root.searchRequest = null;
            if (request.status !== 200) {
                root.searchError = "Location search failed";
                return;
            }

            try {
                const data = JSON.parse(request.responseText);
                const matches = Array.isArray(data.results) ? data.results : [];
                const results = [];
                for (const match of matches) {
                    const location = root.normalizeLocation(match);
                    if (location && !results.some(existing => existing.key === location.key))
                        results.push(location);
                }
                root.searchResults = results.slice(0, 5);
                root.searchError = root.searchResults.length === 0 ? "No locations found" : "";
            } catch (error) {
                root.searchError = "Invalid location response";
            }
        };
        request.open("GET", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(name) + "&count=5&language=en&format=json");
        request.send();
    }

    function addLocation(location) {
        if (!root.locations.some(entry => entry.key === location.key))
            root.locations = root.locations.concat([location]);
        const changed = root.activeLocationKey !== location.key;
        root.activeLocationKey = location.key;
        root.searchResults = [];
        root.searchError = "";
        if (changed)
            root.clearForecast();
        root.saveState();
        root.refreshIfStale();
    }

    function selectLocation(key) {
        if (!root.locations.some(location => location.key === key))
            return;
        root.searchResults = [];
        root.searchError = "";
        if (key === root.activeLocationKey)
            return;
        root.activeLocationKey = key;
        root.clearForecast();
        root.saveState();
        root.refreshForecast();
    }

    function removeLocation(key) {
        const remaining = root.locations.filter(location => location.key !== key);
        if (remaining.length === root.locations.length)
            return;
        root.locations = remaining;
        if (root.activeLocationKey === key) {
            if (root.forecastRequest)
                root.forecastRequest.abort();
            root.forecastRequest = null;
            root.activeLocationKey = remaining.length > 0 ? remaining[0].key : "";
            root.clearForecast();
        }
        root.saveState();
        root.refreshIfStale();
    }

    FileView {
        id: stateFile

        path: Quickshell.env("HOME") + "/.local/state/quickshell/weather.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        onLoaded: root.loadState(text())
        onLoadFailed: root.saveState()
    }
}
