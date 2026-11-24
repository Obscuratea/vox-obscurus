import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The parametric EQ page: pick an output along the top, shape its curve underneath.
Item {
    id: view
    required property var app
    readonly property var outs: app.aIdx.concat(app.bIdx)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            contentWidth: picks.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            Row {
                id: picks
                spacing: 6
                Repeater {
                    model: view.outs
                    Chip {
                        required property int modelData
                        readonly property string name: view.app.nameOf("bus", modelData)
                        app: view.app
                        text: view.app.tagOf("bus", modelData) + (view.width >= 700 ? "  " + name : "")
                        checked: view.app.eqIndex === modelData
                        tip: name
                        onToggled: view.app.eqIndex = modelData
                    }
                }
            }
        }
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: Math.max(height, editor.wantedHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { width: 5; policy: ScrollBar.AsNeeded }
            PeqEditor {
                id: editor
                width: scroller.width - (scroller.contentHeight > scroller.height ? 8 : 0)
                height: scroller.contentHeight
                app: view.app
                embedded: true
                kind: "bus"
                index: view.app.eqIndex
            }
        }
    }
}
