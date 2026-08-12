import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: nav
    required property var theme
    property bool selected: false
    property string glyph: ""
    property string hint: ""

    hoverEnabled: true
    implicitHeight: 58
    leftPadding: 12
    rightPadding: 10

    background: Rectangle {
        radius: 13
        color: nav.selected ? nav.theme.accentSoft : (nav.hovered ? nav.theme.surfaceHover : "transparent")
        border.width: nav.selected ? 1 : 0
        border.color: nav.theme.toneBorder("accent")
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            visible: nav.selected
            width: 3
            height: 28
            radius: 2
            color: nav.theme.accent
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    contentItem: RowLayout {
        spacing: 11
        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 10
            color: nav.selected ? "#FFFFFF" : "transparent"
            border.width: nav.selected ? 1 : 0
            border.color: nav.theme.border
            Text {
                anchors.centerIn: parent
                text: nav.glyph
                color: nav.selected ? nav.theme.accent : nav.theme.textMuted
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: nav.text
                color: nav.selected ? nav.theme.textStrong : nav.theme.text
                font.pixelSize: 13
                font.weight: nav.selected ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: nav.hint
                color: nav.theme.textMuted
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        Text {
            visible: nav.selected
            text: "›"
            color: nav.theme.accent
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
    }
}
