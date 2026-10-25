import QtQuick

// Stereo peak meter from -60 to 0 dB. Turns amber above -6 dB and red near clipping.
Item {
    id: meter
    required property var app
    property var peaks: [0, 0]
    property bool vertical: true
    property real leftLevel: 0
    property real rightLevel: 0

    implicitWidth: vertical ? 12 : 120
    implicitHeight: vertical ? 120 : 10

    function fraction(peak) {
        if (!(peak > 0.00001))
            return 0;
        return Math.max(0, Math.min(1, (20 * Math.log10(peak) + 60) / 60));
    }
    // Jump up instantly, fall back slowly so short peaks stay readable.
    onPeaksChanged: {
        leftLevel = Math.max(fraction(peaks[0]), leftLevel - 0.02);
        rightLevel = Math.max(fraction(peaks[1]), rightLevel - 0.02);
    }

    Repeater {
        model: 2
        Rectangle {
            id: bar
            required property int index
            readonly property real level: index === 0 ? meter.leftLevel : meter.rightLevel
            readonly property real thickness: ((meter.vertical ? meter.width : meter.height) - 2) / 2

            x: meter.vertical ? index * (thickness + 2) : 0
            y: meter.vertical ? 0 : index * (thickness + 2)
            width: meter.vertical ? thickness : meter.width
            height: meter.vertical ? meter.height : thickness
            color: meter.app.line

            Rectangle {
                x: 0
                y: meter.vertical ? parent.height * (1 - bar.level) : 0
                width: meter.vertical ? parent.width : parent.width * bar.level
                height: meter.vertical ? parent.height * bar.level : parent.height
                color: bar.level > 0.97 ? meter.app.danger : bar.level > 0.9 ? meter.app.warning : meter.app.accent
            }
        }
    }
}
