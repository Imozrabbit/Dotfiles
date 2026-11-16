function parseFrame(text) {
    if (typeof text !== "string" || text.length > 80)
        return null;
    const values = text.replace(/;$/, "").split(";");
    if (values.length !== 16)
        return null;
    const levels = [];
    for (const value of values) {
        if (!/^[0-9]{1,4}$/.test(value) || Number(value) > 1000)
            return null;
        levels.push(Number(value) / 1000);
    }
    return levels;
}

function configuration(outputName) {
    if (typeof outputName !== "string" || !/^[A-Za-z0-9_.:-]{1,512}$/.test(outputName))
        return null;
    return "[general]\nbars = 16\nframerate = 30\nsleep_timer = 1\n"
        + "[input]\nmethod = pipewire\nsource = " + outputName + ".monitor\n"
        + "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\n"
        + "channels = mono\nmono_option = average\nascii_max_range = 1000\n"
        + "bar_delimiter = 59\nframe_delimiter = 10\n";
}
