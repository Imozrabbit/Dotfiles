#!/usr/bin/env python3
"""Offscreen UI checks: no USB queries, network requests or real credentials."""

import json
from math import ceil, floor
import os
from pathlib import Path
import re
import tempfile


def check():
    # Isolation must precede Qt imports/application creation.
    with tempfile.TemporaryDirectory(prefix="desktop-status-check-", dir="/tmp/opencode") as private:
        for name in ("XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR", "XDG_RUNTIME_DIR"):
            path = Path(private, name)
            path.mkdir(mode=0o700)
            os.environ[name] = str(path)
        os.environ["QT_QPA_PLATFORM"] = "offscreen"
        os.environ["QT_QUICK_BACKEND"] = "software"
        os.environ["QML_DISABLE_DISK_CACHE"] = "1"

        from PySide6.QtCore import QDateTime, QEvent, QObject, QPointF, QRectF, Qt, QUrl
        from PySide6.QtGui import QColor, QGuiApplication
        from PySide6.QtQml import QQmlComponent, QQmlEngine
        from PySide6.QtQuick import QQuickItem, QQuickWindow
        from PySide6.QtTest import QTest

        app = QGuiApplication([])
        engine = QQmlEngine()
        root = Path(__file__).resolve().parents[1]
        panel_path = root / "ui/StatusPanel.qml"
        assert panel_path.is_file(), "Desktop status panel not implemented"

        components = []
        objects = []

        def create(path, properties=None, source=None):
            component = QQmlComponent(engine)
            if source is None:
                component.loadUrl(QUrl.fromLocalFile(str(path)))
            else:
                component.setData(source.encode(), QUrl.fromLocalFile(str(path)))
            components.append(component)
            while component.status() == QQmlComponent.Loading:
                app.processEvents()
            assert not component.isError(), "\n".join(error.toString() for error in component.errors())
            properties = {name: engine.evaluate("(" + json.dumps(value) + ")") if isinstance(value, dict) else value
                          for name, value in (properties or {}).items()}
            item = component.createWithInitialProperties(properties)
            assert item is not None, "\n".join(error.toString() for error in component.errors())
            objects.append(item)
            return item

        config = create(root / "Config.qml")

        # Exercise the production surface's bindings on an offscreen Qt Window.
        # PanelWindow itself requires a Wayland backend, unavailable offscreen.
        shell = (root / "shell.qml").read_text()
        visible_binding = re.search(r"^\s*visible:\s*(.+)$", shell, re.MULTILINE).group(1)
        height_binding = re.search(r"^\s*implicitHeight:\s*(.+)$", shell, re.MULTILINE).group(1)
        startup = create(root / "tests/startup.qml", {"config": config}, source=f'''
import QtQuick
import QtQuick.Window
import "{root.as_uri()}" as Desktop
import "{(root / 'ui').as_uri()}" as Ui
Window {{
    id: window
    required property Desktop.Config config
    property real availableWidth: 260
    property real availableHeight: 240
    QtObject {{ id: root; property Desktop.Config config: window.config }}
    visible: {visible_binding}
    width: 260
    height: {height_binding}
    Ui.StatusPanel {{
        id: panel
        anchors.fill: parent
        config: root.config
        currentDate: new Date()
        quotaService: null
        mouseService: null
        micService: null
    }}
}}
''')
        QTest.qWait(50)
        assert startup.isVisible() and startup.height() > 1, "Surface must show before its first layout polish"
        for name in ("quotaEnabled", "mouseBatteryEnabled", "micBatteryEnabled"):
            config.setProperty(name, False)
        QTest.qWait(20)
        assert not startup.isVisible(), "No surface needed when all modules are disabled"
        for name in ("quotaEnabled", "mouseBatteryEnabled", "micBatteryEnabled"):
            config.setProperty(name, True)
        QTest.qWait(20)
        assert startup.isVisible() and startup.height() > 1
        startup.close()

        now = 1_800_000_000_000
        panel = create(panel_path, {
            "config": config,
            "currentDate": QDateTime.fromMSecsSinceEpoch(now),
            "quotaService": {"available": True, "error": "", "snapshot": {
                "weekly": {"usedPercent": 66, "resetAt": now + 194400000},
                "fiveHour": {"usedPercent": 18, "resetAt": now + 5040000},
                "bankedResets": 2, "fetchedAt": now, "plan": "plus", "allowed": True, "limitReached": False,
            }},
            "mouseService": {"available": True, "percentage": 79, "charging": True,
                             "connection": "wired", "error": ""},
            "micService": {"available": True, "error": "", "transmitters": [
                {"id": "tx1", "level": 1, "charging": False},
                {"id": "tx2", "level": 7, "charging": True},
                {"id": "tx3", "level": None, "charging": True},
                {"id": "tx4", "level": 4, "charging": False},
            ]},
        })
        window = QQuickWindow()
        window.resize(260, 400)
        panel.setParentItem(window.contentItem())
        window.show()
        panel.setWidth(260)
        panel.setHeight(240)
        QTest.qWait(50)

        def meter(name):
            def find(item):
                if item.objectName() == name:
                    return item
                for child in item.childItems():
                    found = find(child)
                    if found is not None:
                        return found
                return None

            item = find(panel)
            assert item is not None, f"Missing meter: {name}"
            return item

        def check_colors(name, filled):
            item = meter(name)
            children = item.childItems()
            assert all(child.property("color") == QColor("#f2efe1ff") for child in children[:2]), name
            colors = [child.property("color") for child in children[2].childItems() if child.property("color") is not None]
            assert colors == ([QColor("#cfcfcfff")] * filled
                              + [QColor("#302b40")] * (item.property("segments") - filled)), name

        for name, filled in (("quotaWeekly", 7), ("quotaFiveHour", 16), ("mouseBattery", 16),
                             ("mic-tx1", 7), ("mic-tx2", 1), ("mic-tx3", 0)):
            check_colors(name, filled)

        assert meter("quotaWeekly").property("valueText") == "2d 6h"
        assert meter("quotaFiveHour").property("valueText") == "1h 24m"
        assert abs(meter("quotaWeekly").property("fraction") - 0.34) < 0.0001
        assert abs(meter("quotaFiveHour").property("fraction") - 0.82) < 0.0001

        for remaining_ms, text in ((3600000, "1h 0m"), (120000, "2m"), (59999, "1m"), (0, "Due"), (-1, "Due")):
            panel.setProperty("currentDate", QDateTime.fromMSecsSinceEpoch(now + 5040000 - remaining_ms))
            app.processEvents()
            assert meter("quotaFiveHour").property("valueText") == text
            assert abs(meter("quotaFiveHour").property("fraction") - 0.82) < 0.0001
        panel.setProperty("currentDate", QDateTime.fromMSecsSinceEpoch(now))

        original_quota = panel.property("quotaService")
        unknown_reset = original_quota.toVariant()
        unknown_reset["snapshot"]["weekly"]["resetAt"] = None
        unknown_reset["snapshot"]["fiveHour"] = None
        panel.setProperty("quotaService", engine.evaluate("(" + json.dumps(unknown_reset) + ")"))
        app.processEvents()
        assert meter("quotaWeekly").property("valueText") == "N/A"
        assert abs(meter("quotaWeekly").property("fraction") - 0.34) < 0.0001
        assert meter("quotaFiveHour").property("valueText") == "N/A"
        assert meter("quotaFiveHour").property("fraction") == -1
        check_colors("quotaWeekly", 7)
        check_colors("quotaFiveHour", 0)
        panel.setProperty("quotaService", original_quota)
        app.processEvents()
        assert meter("quotaWeekly").property("valueText") == "2d 6h"
        assert meter("quotaFiveHour").property("valueText") == "1h 24m"

        assert meter("mouseBattery").property("valueText") == "79% +"
        assert meter("mic-tx1").property("valueText") == "FULL"
        assert meter("mic-tx1").property("fraction") == 1
        assert abs(meter("mic-tx2").property("fraction") - 1 / 7) < 0.0001
        assert meter("mic-tx3").property("fraction") == -1, (meter("mic-tx3").property("fraction"), meter("mic-tx3").property("valueText"))
        assert meter("mic-tx3").property("valueText") == "N/A +", "Unknown level must not hide known charging state"

        quota = panel.property("quotaService")
        quota.setProperty("refreshCount", 0)
        quota.setProperty("refresh", engine.evaluate("(function(force) { this.refreshCount++; this.lastForce = force; })"))
        weekly = meter("quotaWeekly")
        point = weekly.mapToScene(QPointF(weekly.width() / 2, weekly.height() / 2)).toPoint()
        QTest.mouseMove(window, point)
        QTest.qWait(350)
        assert quota.property("refreshCount").toInt() == 0, "Hover must not query collectors"
        assert not any("ToolTip" in child.metaObject().className() and child.property("visible")
                       for child in panel.findChildren(QObject)), "Hover must not show a tooltip"
        QTest.mouseClick(window, Qt.LeftButton, pos=point)
        QTest.qWait(20)
        assert quota.property("refreshCount").toInt() == 1, "Click must request one refresh"
        assert quota.property("lastForce").toBool(), "Click must bypass refresh cooldown"

        column = panel.findChild(QQuickItem, "statusColumn")
        assert column is not None and column.height() > 0
        for section in column.childItems():
            assert section.childItems()[0].property("color") == QColor("#a7a2ba"), "Keep section titles unchanged"
        for width, height in ((260, 240), (180, 180), (320, 320)):
            window.resize(width, height)
            panel.setWidth(width)
            panel.setHeight(height)
            QTest.qWait(20)
            bounds = column.mapRectToItem(panel, QRectF(0, 0, column.width(), column.height()))
            assert bounds.bottom() <= height + 0.1, (height, bounds)
            assert bounds.right() <= panel.width() + 0.1, bounds

        for name in ("quotaService", "mouseService", "micService"):
            panel.setProperty(name, None)
        QTest.qWait(20)
        for name in ("quotaWeekly", "quotaFiveHour", "mouseBattery", "mic-unavailable"):
            assert meter(name).property("valueText") == "N/A", name
            assert meter(name).property("fraction") == -1, name

        # Run the actual sibling weather row with fixture data, without its
        # Wayland surface or network service. Standalone installs may omit it.
        weather_path = root.parent / "weather/WeatherOsd.qml"
        if weather_path.is_file():
            source = weather_path.read_text()
            row_source = source[source.index("        RowLayout {"):source.rfind("\n    }")]
            weather = create(root / "tests/weather.qml", source='''
import QtQuick
import QtQuick.Layouts
Item {
    width: 260
    height: 40
    QtObject {
        id: wx
        objectName: "weatherFixture"
        property real nowTempC: 8
        property var tminC: [7]
        property var tmaxC: [16]
        property int nowCode: 0
        function decode(code) { return { i: " " }; }
    }
''' + row_source + '\n}')
            weather.setParentItem(window.contentItem())
            wx = weather.findChild(QObject, "weatherFixture")
            row = weather.childItems()[0]
            for current, minimum, maximum in ((8, 7, 16), (-9, -12, -1), (32, 20, 36)):
                wx.setProperty("nowTempC", current)
                wx.setProperty("tminC", [minimum])
                wx.setProperty("tmaxC", [maximum])
                QTest.qWait(20)
                assert abs(row.x()) < 0.1, ("Weather left edge", row.x())
                assert abs(row.x() + row.width() - 260) < 0.1, ("Weather right edge", row.x(), row.width())
                last = row.childItems()[-1]
                assert abs(last.x() + last.width() - 260) < 0.1, "Last temperature must align with status values"
            # Include monitor-relative positioning and the real date row. Paint
            # onto a wider canvas so overflow cannot masquerade as alignment.
            clock_path = root.parent / "clock/shell.qml"
            if clock_path.is_file():
                clock_source = clock_path.read_text()
                date_row = clock_source[clock_source.index("                Row {"):clock_source.index("                // Clock (centered)")]
                clock_width = int(re.search(r"implicitWidth:\s*(\d+)", clock_source).group(1))
                clock_left = int(re.search(r"\bleft:\s*(\d+)", clock_source).group(1))
                date_size = int(re.search(r"property int dateSize:\s*(\d+)", clock_source).group(1))
                date_ink_adjustment = int(re.search(r"property int dateInkAdjustment:\s*(\d+)", clock_source).group(1))
                # HDMI-A-1 is 515 logical pixels wide after its rotation.
                column_left = 515 - config.property("rightMargin") - 260
                date_view = create(root / "tests/date.qml", source=f'''
import QtQuick
Item {{
    id: window
    width: {clock_width}
    height: 60
    property int dateSize: {date_size}
    property int dateInkAdjustment: {date_ink_adjustment}
    QtObject {{ id: clock; objectName: "clockFixture"; property date date: new Date(2026, 9, 22) }}
    {date_row}
}}
''')
                date_view.setParentItem(window.contentItem())
                date_view.setX(clock_left - column_left)
                date_view.setY(15)
                date_model = date_view.findChild(QObject, "clockFixture")
                weather_right = int(re.search(r"\bright:\s*(\d+)", source).group(1))
                weather.setX(config.property("rightMargin") - weather_right)
                weather.setY(57)
                panel.setY(110)
                panel.setWidth(260)
                panel.setHeight(282)
                window.resize(300, 400)
                window.setColor(QColor("black"))

                def painted_right(item, image):
                    rect = item.mapRectToScene(QRectF(0, 0, item.width(), item.height()))
                    pixels = [x for y in range(max(0, floor(rect.top())), min(image.height(), ceil(rect.bottom())))
                              for x in range(max(0, floor(rect.left())), min(image.width(), ceil(rect.right()) + 8))
                              if max(image.pixelColor(x, y).getRgb()[:3]) > 20]
                    assert pixels, item
                    return max(pixels)

                for month in range(1, 13):
                    maximum = (16, -1, 36)[(month - 1) % 3]
                    mouse = (76, None, 50)[(month - 1) % 3]
                    date_model.setProperty("date", QDateTime.fromString(f"2026-{month:02}-22", "yyyy-MM-dd"))
                    wx.setProperty("tmaxC", [maximum])
                    panel.setProperty("quotaService", quota)
                    panel.setProperty("mouseService", engine.evaluate("(" + json.dumps({
                        "available": mouse is not None, "percentage": mouse or 0,
                        "charging": mouse == 50, "connection": "wired", "error": "",
                    }) + ")"))
                    panel.setProperty("micService", engine.evaluate("(" + json.dumps({
                        "available": True, "error": "", "transmitters": [{
                            "id": "tx1", "level": (1, 7, None)[(month - 1) % 3],
                            "charging": month % 3 != 1,
                        }],
                    }) + ")"))
                    QTest.qWait(60)
                    assert meter("mouseBattery").property("valueText") == ("76%", "N/A", "50% +")[(month - 1) % 3]
                    assert meter("mic-tx1").property("valueText") == ("FULL", "L7 +", "N/A +")[(month - 1) % 3]
                    image = window.grabWindow()
                    assert not image.isNull()
                    edges = {
                        "date": painted_right(date_view.childItems()[0].childItems()[-1], image),
                        "weather": painted_right(row.childItems()[-1], image),
                        "quota": painted_right(meter("quotaWeekly").childItems()[1], image),
                        "quota5h": painted_right(meter("quotaFiveHour").childItems()[1], image),
                        "mouse": painted_right(meter("mouseBattery").childItems()[1], image),
                        "mic": painted_right(meter("mic-tx1").childItems()[1], image),
                        "meter": painted_right(meter("mouseBattery").childItems()[2], image),
                    }
                    assert max(edges.values()) - min(edges.values()) <= 1, ("Painted right edges", edges)

                sections = [child for child in column.childItems() if child.property("spacing") is not None]
                assert len(sections) == 3
                for section in sections:
                    header = section.childItems()[0]
                    y = floor(header.mapToScene(QPointF(0, header.height() / 2)).y())
                    assert max(image.pixelColor(250, y).getRgb()[:3]) == 0, "Section backgrounds must stay transparent"
                for before, after in zip(sections, sections[1:]):
                    assert after.y() - before.y() - before.height() >= 20, "Use whitespace between groups"
                    bottom = before.mapRectToScene(QRectF(0, 0, before.width(), before.height())).bottom()
                    top = after.mapRectToScene(QRectF(0, 0, after.width(), after.height())).top()
                    assert all(max(image.pixelColor(x, y).getRgb()[:3]) == 0
                               for y in range(ceil(bottom) + 2, floor(top) - 1) for x in range(260)), "No separators or fills"
                print("PASS: painted date/weather/status edges, transparent whitespace grouping")

        # Destroy QML objects before their engine and before disposable paths vanish.
        window.close()
        for item in reversed(objects):
            item.deleteLater()
        app.sendPostedEvents(None, QEvent.DeferredDelete)
        del window, engine, app
        print("PASS: startup, module switches, reset countdowns, quota/battery states, click-only refresh, bounded layout")


if __name__ == "__main__":
    check()
