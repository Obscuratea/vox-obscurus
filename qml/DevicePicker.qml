import QtQuick
import QtQuick.Controls.Basic

// Device dropdown. An unplugged device stays listed as "Not connected", so the choice isn't lost.
ComboBox {
    id: box
    required property var app
    property var devices: []
    property string current: ""
    signal picked(string name)

    readonly property var entries: {
        const list = [{ name: "", description: "None" }].concat(devices);
        if (current !== "" && !devices.some(d => d.name === current))
            list.push({ name: current, description: "Not connected · " + current });
        return list;
    }

    function indexOfCurrent() {
        return entries.findIndex(d => d.name === current);
    }

    model: entries
    textRole: "description"
    valueRole: "name"
    currentIndex: indexOfCurrent()
    implicitHeight: 30
    font.pixelSize: 12
    hoverEnabled: true

    onActivated: index => {
        picked(entries[index].name);
        // Choosing an item replaces the binding; put it back so it keeps following the settings.
        currentIndex = Qt.binding(indexOfCurrent);
    }

    background: Rectangle {
        color: "transparent"
        border.color: box.hovered || box.popup.visible ? box.app.accent : box.app.line
    }
    contentItem: Text {
        leftPadding: 10
        rightPadding: 26
        text: box.displayText
        color: box.app.ink
        font: box.font
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    indicator: Text {
        x: box.width - width - 10
        anchors.verticalCenter: box.verticalCenter
        text: "▾"
        color: box.app.dim
        font.pixelSize: 12
    }
    delegate: ItemDelegate {
        id: item
        required property var modelData
        required property int index
        width: box.width
        highlighted: box.highlightedIndex === index
        contentItem: Text {
            text: item.modelData.description
            color: item.highlighted ? box.app.accentInk : box.app.ink
            font: box.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { color: item.highlighted ? box.app.accent : "transparent" }
    }
    popup.background: Rectangle {
        color: box.app.bg
        border.color: box.app.line
    }
}
