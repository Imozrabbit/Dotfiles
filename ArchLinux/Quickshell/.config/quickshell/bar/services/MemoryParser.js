function parseMeminfo(text) {
    const values = Object.create(null);
    for (const line of String(text).split("\n")) {
        const match = line.match(/^([A-Za-z]+):\s+(\d+) kB\s*$/);
        if (match)
            values[match[1]] = Number(match[2]);
    }

    const valid = name => Number.isSafeInteger(values[name]) && values[name] >= 0;
    let memory = null;
    if (valid("MemTotal") && valid("MemAvailable")) {
        const total = values.MemTotal;
        const used = total - values.MemAvailable;
        if (total > 0 && used >= 0 && used <= total && values.MemAvailable <= total)
            memory = { total: total, used: used, available: values.MemAvailable };
    }

    let swap = null;
    if (valid("SwapTotal") && valid("SwapFree") && values.SwapFree <= values.SwapTotal)
        swap = { total: values.SwapTotal, used: values.SwapTotal - values.SwapFree };

    return { memory: memory, swap: swap };
}
