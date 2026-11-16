pragma ComponentBehavior: Bound
import QtQuick
import "../../common/Theme.js" as Theme

Canvas {
    id: root

    property var levels: []
    property var themeColors: Theme.colors
    property real radius: 0
    readonly property bool valid: {
        if (!root.levels || root.levels.length !== 16)
            return false;
        for (let index = 0; index < 16; ++index) {
            const level = root.levels[index];
            if (typeof level !== "number" || !Number.isFinite(level) || level < 0 || level > 1)
                return false;
        }
        return true;
    }
    visible: root.valid && width > 0 && height > 0
    opacity: 0.12
    antialiasing: true

    onLevelsChanged: if (visible)
        requestPaint()
    onThemeColorsChanged: if (visible)
        requestPaint()
    onRadiusChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available)
        requestPaint()
    onVisibleChanged: if (visible)
        requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        if (!root.valid)
            return;
        const r = Math.max(0, Math.min(root.radius, width / 2, height / 2));
        ctx.save();
        ctx.beginPath();
        ctx.roundedRect(0, 0, width, height, r, r);
        ctx.clip();
        ctx.beginPath();
        ctx.moveTo(0, height);
        ctx.lineTo(0, height * (1 - root.levels[0]));
        for (let index = 0; index < 15; ++index) {
            const x = index * width / 15;
            const y = height * (1 - root.levels[index]);
            const nextY = height * (1 - root.levels[index + 1]);
            // Midpoint quadratics round peaks without overshooting sample bounds.
            ctx.quadraticCurveTo(x, y, (index + 0.5) * width / 15, (y + nextY) / 2);
        }
        const lastY = height * (1 - root.levels[15]);
        ctx.quadraticCurveTo(width, lastY, width, lastY);
        ctx.lineTo(width, height);
        ctx.closePath();
        ctx.fillStyle = root.themeColors.mediaSpectrum;
        ctx.fill();
        ctx.restore();
    }
}
