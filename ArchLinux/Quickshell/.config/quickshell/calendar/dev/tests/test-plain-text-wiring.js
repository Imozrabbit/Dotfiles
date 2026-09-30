const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const ui = path.join(__dirname, "../../ui")

function assertPlainText(file, binding) {
    const source = fs.readFileSync(path.join(ui, file), "utf8")
    let bindingIndex = source.indexOf(binding)
    assert.notEqual(bindingIndex, -1, `${file} missing ${binding}`)
    while (bindingIndex !== -1) {
        const objectStart = source.lastIndexOf("Text {", bindingIndex)
        assert.notEqual(objectStart, -1, `${file} binding not inside Text object: ${binding}`)
        const openingBrace = source.indexOf("{", objectStart)
        let depth = 0
        let closingBrace = -1
        for (let index = openingBrace; index < source.length; index++) {
            if (source[index] === "{") depth++
            if (source[index] === "}" && --depth === 0) {
                closingBrace = index
                break
            }
        }
        assert.notEqual(closingBrace, -1, `${file} has unclosed Text object`)
        assert.ok(bindingIndex < closingBrace, `${file} binding not inside Text object: ${binding}`)
        assert.match(source.slice(objectStart, closingBrace + 1), /textFormat:\s*Text\.PlainText/,
            `${file} renders untrusted binding as rich text: ${binding}`)
        bindingIndex = source.indexOf(binding, bindingIndex + binding.length)
    }
}

for (const [file, bindings] of Object.entries({
    "CalendarWindow.qml": ["text: calendarEntry.modelData.name"],
    "AgendaView.qml": ["text: CalendarMath.holidayLabel(dayRow.modelData.holidays)", "parent.modelData.location ? parent.modelData.title"],
    "MonthView.qml": ["text: root.eventLabel(parent.modelData)", "text: CalendarMath.holidayLabel(dayColumn.modelData.holidays)"],
    "WeekView.qml": ["text: CalendarMath.holidayLabel(allDayColumn.modelData.holidays)"],
    "EventCard.qml": ["text: root.eventData.title", "text: root.eventData.location"],
    "EventDetailsPanel.qml": ["text: root.details ? root.details.title", "text: root.details ? root.details.calendarName", "text: root.details ? root.details.location", "text: root.details ? root.details.description", "text: \"- \" + modelData", "text: root.details ? root.details.status", "text: root.actionError"],
    "ConflictResolutionPanel.qml": ["text: root.conflict ? root.conflict.uid", "text: root.value(versionCard.modelData.data, \"title\")", "text: root.value(versionCard.modelData.data, parent.modelData.key)", "text: root.conflictService.errorMessage"],
    "CalendarManagerPanel.qml": ["text: root.errorMessage.length > 0 ? root.errorMessage", "text: calendarEntry.modelData.name", "text: calendarEntry.modelData.type +", "text: root.sourcePath.length > 0 ? root.sourcePath", "text: root.pickerPath", "text: (entry.fileIsDir ? \"  \" : \"  \") + entry.fileName"],
    "EventEditorPanel.qml": ["text: calendarCombo.displayText", "text: calendarCombo.textAt(calendarOption.index)", "text: root.errorMessage"]
})) {
    for (const binding of bindings)
        assertPlainText(file, binding)
}

console.log("Plain-text UI tests passed")
