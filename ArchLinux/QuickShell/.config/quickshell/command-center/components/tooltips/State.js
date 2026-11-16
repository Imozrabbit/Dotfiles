.pragma library

let current = null;

function claim(tooltip) {
    if (current && current !== tooltip)
        current.close();
    current = tooltip;
}

function release(tooltip) {
    if (current === tooltip)
        current = null;
}
