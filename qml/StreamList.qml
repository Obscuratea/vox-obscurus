import QtQuick
import QtQuick.Layouts

// The programs currently using one of our devices, each in a pill with its icon. Playing streams
// get a mute button; recording streams (who is listening to a B mic) are just listed.
Item {
    id: list
    required property var app
    required property string target
    property bool mutable: true
    property string emptyText: "Nothing playing"
    readonly property var items: app.streams.filter(s => s.target === target)

    Text {
        visible: list.items.length === 0
        anchors.fill: parent
        text: list.emptyText
        color: list.app.dim
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    ListView {
        anchors.fill: parent
        visible: list.items.length > 0
        clip: true
        spacing: 6
        model: list.items
        delegate: Rectangle {
            id: pill
            required property var modelData
            width: ListView.view.width
            height: 34
            radius: list.app.diamond ? 0 : height / 2
            color: list.app.soft ? list.app.tonal : list.app.hover
            border.color: list.app.edge
            opacity: modelData.muted ? 0.6 : 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 5
                spacing: 8

                // The first letter shows behind the icon, so a program with no icon still gets a badge.
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: pill.modelData.icon !== "" ? "transparent" : Qt.alpha(list.app.accent, 0.25)
                    Text {
                        visible: pill.modelData.icon === ""
                        anchors.centerIn: parent
                        text: pill.modelData.name.charAt(0).toUpperCase()
                        color: list.app.ink
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Image {
                        anchors.fill: parent
                        source: pill.modelData.icon
                        sourceSize: Qt.size(44, 44)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: pill.modelData.name
                    color: list.app.ink
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    font.strikeout: pill.modelData.muted
                }
                Chip {
                    visible: list.mutable
                    app: list.app
                    text: pill.modelData.muted ? (list.app.t("Muted")) : (list.app.t("Mute"))
                    checked: pill.modelData.muted
                    implicitHeight: 24
                    radius: 12
                    onColor: list.app.danger
                    tip: "Mute just " + pill.modelData.name
                    onToggled: list.app.muteStream(pill.modelData.id, !pill.modelData.muted)
                }
            }
        }
    }
}
