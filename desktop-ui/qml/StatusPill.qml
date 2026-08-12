import QtQuick
import QtQuick.Layouts

Rectangle {
    id: pill
    required property var theme
    property string label: "Ready"
    property string tone: "neutral"
    property bool dotVisible: true

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 28
    radius: 14
    color: theme.toneBackground(tone)
    border.width: 1
    border.color: theme.toneBorder(tone)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Rectangle {
            visible: pill.dotVisible
            width: 7
            height: 7
            radius: 4
            color: theme.toneForeground(pill.tone)
        }
        Text {
            text: pill.label
            color: theme.toneForeground(pill.tone)
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
}
