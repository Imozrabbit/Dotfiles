function nextPercent(currentPercent, direction) {
    const step = direction > 0 ? 10 : direction < 0 ? -10 : 0
    return Math.max(50, Math.min(150, currentPercent + step))
}

function hourHeight(percent) {
    return 72 * percent / 100
}

function wheelDirection(controlPressed, deltaY) {
    if (!controlPressed || deltaY === 0)
        return 0
    return deltaY > 0 ? 1 : -1
}

function nextWeeksPerPage(currentWeeks, direction) {
    const step = direction > 0 ? -1 : direction < 0 ? 1 : 0
    return Math.max(2, Math.min(6, currentWeeks + step))
}

function anchoredOffset(contentY, viewportHeight, oldHeight, newHeight,
        maxOffset) {
    const centerHour = (contentY + viewportHeight / 2) / oldHeight
    const offset = centerHour * newHeight - viewportHeight / 2
    return Math.max(0, Math.min(Math.max(0, maxOffset), offset))
}

function trailingViewportPadding(viewportHeight, lastRowHeight) {
    return Math.max(0, viewportHeight - lastRowHeight)
}

function separatorVisible(position, viewportHeight, thickness) {
    return position > thickness && position < viewportHeight - thickness
}

if (typeof module !== "undefined") {
    module.exports = {
        anchoredOffset,
        hourHeight,
        nextPercent,
        nextWeeksPerPage,
        separatorVisible,
        trailingViewportPadding,
        wheelDirection
    }
}
