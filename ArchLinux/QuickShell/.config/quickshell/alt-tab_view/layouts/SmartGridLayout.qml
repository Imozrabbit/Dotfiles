pragma Singleton
import Quickshell

Singleton {
    id: root

    function doLayout(windowList, outerWidth, outerHeight) {
        if (windowList.length === 0)
            return [];
        if (outerWidth <= 0 || outerHeight <= 0)
            return [];

        var normalList = [];
        var specialList = [];

        for (var i = 0; i < windowList.length; i++) {
            var item = windowList[i];
            if (item.workspaceId < 0)
                specialList.push(item);
            else
                normalList.push(item);
        }

        var result = [];

        function layoutSection(items, sectionY, sectionH, sectionName) {
            var N = items.length;
            if (N === 0)
                return [];

            var gap = Math.min(outerWidth * 0.03, outerHeight * 0.03);
            var contentScale = 0.9;
            var usableW = outerWidth * contentScale;
            var usableH = sectionH * contentScale;

            var TARGET_ASPECT = 16.0 / 9.0;
            var bestCols = 1;
            var bestRows = 1;
            var bestScale = 0;

            for (var cols = 1; cols <= N; cols++) {
                var rows = Math.ceil(N / cols);

                var availW = usableW - gap * (cols - 1);
                var availH = usableH - gap * (rows - 1);

                if (availW <= 0 || availH <= 0)
                    continue;
                var cellW = availW / cols;
                var cellH = availH / rows;

                var scaleW = cellW / TARGET_ASPECT;
                var scaleH = cellH / 1.0;
                var currentScale = Math.min(scaleW, scaleH);

                if (currentScale > bestScale) {
                    bestScale = currentScale;
                    bestCols = cols;
                    bestRows = rows;
                }
            }

            var finalAvailW = usableW - gap * (bestCols - 1);
            var finalAvailH = usableH - gap * (bestRows - 1);
            var maxCellW = finalAvailW / bestCols;
            var maxCellH = finalAvailH / bestRows;

            var totalGridContentH = bestRows * maxCellH + (bestRows - 1) * gap;
            var startOffsetY = sectionY + (sectionH - totalGridContentH) / 2;

            var sectionResult = [];

            for (var r = 0; r < bestRows; r++) {
                var rowItems = [];
                var startIndex = r * bestCols;
                var endIndex = Math.min(startIndex + bestCols, N);

                if (startIndex >= N)
                    break;
                var totalRowContentWidth = 0;

                for (var j = startIndex; j < endIndex; j++) {
                    var sectionItem = items[j];
                    var w0 = (sectionItem.width && sectionItem.width > 0) ? sectionItem.width : 100;
                    var h0 = (sectionItem.height && sectionItem.height > 0) ? sectionItem.height : 100;

                    var scale = Math.min(maxCellW / w0, maxCellH / h0);

                    var thumbW = w0 * scale;
                    var thumbH = h0 * scale;

                    rowItems.push({
                        originalItem: sectionItem,
                        width: thumbW,
                        height: thumbH,
                        index: j,
                        col: j - startIndex
                    });

                    totalRowContentWidth += thumbW;
                }

                if (rowItems.length > 1)
                    totalRowContentWidth += (rowItems.length - 1) * gap;

                var currentX = (outerWidth - totalRowContentWidth) / 2;
                var cellAbsY = startOffsetY + r * (maxCellH + gap);

                for (var k = 0; k < rowItems.length; k++) {
                    var rItem = rowItems[k];
                    var currentY = cellAbsY + (maxCellH - rItem.height) / 2;

                    sectionResult.push({
                        win: rItem.originalItem.win,
                        x: currentX,
                        y: currentY,
                        width: rItem.width,
                        height: rItem.height,
                        rowIndex: r,
                        colIndex: rItem.col,
                        isSpecialWorkspace: rItem.originalItem.workspaceId < 0,
                        sectionName: sectionName
                    });

                    currentX += rItem.width + gap;
                }
            }

            return sectionResult;
        }

        if (normalList.length > 0 && specialList.length > 0) {
            var normalH = outerHeight * 0.72;
            var specialH = outerHeight * 0.22;
            var separatorGap = outerHeight * 0.06;

            result = result.concat(layoutSection(normalList, 0, normalH, "normal"));
            result = result.concat(layoutSection(specialList, normalH + separatorGap, specialH, "special"));
        } else if (specialList.length > 0) {
            result = layoutSection(specialList, 0, outerHeight, "special");
        } else {
            result = layoutSection(normalList, 0, outerHeight, "normal");
        }

        return result;
    }
}
