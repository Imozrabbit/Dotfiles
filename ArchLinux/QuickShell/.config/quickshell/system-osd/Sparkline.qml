pragma ComponentBehavior: Bound
import QtQuick

Canvas {
    id: s
    // Public API
    property var samples: []          // array of numbers
    property real minValue: NaN       // optional manual scaling
    property real maxValue: NaN
    property color lineColor
    property real lineWidth

    // Padding inside the graph
    property int pad: 2

    onSamplesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function _min(arr) {
        var m = Infinity;
        for (var i = 0; i < arr.length; i++)
            if (arr[i] < m)
                m = arr[i];
        return m;
    }
    function _max(arr) {
        var m = -Infinity;
        for (var i = 0; i < arr.length; i++)
            if (arr[i] > m)
                m = arr[i];
        return m;
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        var n = samples.length;
        if (n < 2)
            return;
        var minV = isNaN(minValue) ? _min(samples) : minValue;
        var maxV = isNaN(maxValue) ? _max(samples) : maxValue;
        var range = maxV - minV;
        if (range <= 0)
            range = 1;

        var w = width - 2 * pad;
        var h = height - 2 * pad;
        if (w <= 1 || h <= 1)
            return;
        ctx.lineWidth = lineWidth;
        ctx.strokeStyle = lineColor;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";

        ctx.beginPath();

        for (var i = 0; i < n; i++) {
            var x = pad + (w * i) / (n - 1);
            var t = (samples[i] - minV) / range;
            var y = pad + h * (1 - t);

            if (i === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }

        ctx.stroke();
    }
}
