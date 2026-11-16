.pragma library

const iconFont = "JetBrainsMono Nerd Font";
const textFont = "Atkinson Hyperlegible Next";
const panel = "#0f1416";
// Clavis dark colors with quiet surface levels and no decorative lines.
const colors = {
    panelBorder: "#00000000",
    section: "#40171c1f",
    sectionAlt: "#40171c1f",
    mediaSurface: "#661b2023",
    mediaSpectrum: "#88d0ec",
    contextMenuBackground: "#1b2023",
    notificationSurface: "#661b2023",
    toastBackground: "#8c161616",
    toastButtonBackground: "#80343b40",
    sectionBorder: "#00000000",
    text: "#dee3e6",
    muted: "#bfc8cc",
    tile: "#661b2023",
    tileHover: "#992f3437",
    gridTile: "#661b2023",
    gridTileHover: "#992f3437",
    sliderTrack: "#661b2023",
    tileActive: "#88d0ec",
    onActive: "#003544",
    tileBorder: "#00000000",
    activeBorder: "#00000000",
    hoverBorder: "#00000000",
    bevel: "#00000000",
    danger: "#ffb4ab",
    warning: "#c3c3eb",
    powerLock: "#88d0ec",
    powerLogout: "#ffb786",
    powerSuspend: "#f2d58a",
    powerHibernate: "#a8c7fa"
};
const radius = 10;

function resolveColors(overrides) {
    const palette = {};
    for (const key of Object.keys(colors))
        palette[key] = overrides && overrides[key] !== undefined ? overrides[key] : colors[key];
    return palette;
}
