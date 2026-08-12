import QtQuick
import QtQuick.Controls

Button {
    id: control
    required property var theme
    property string tone: "default"
    property string glyph: ""

    hoverEnabled: true
    implicitHeight: 40
    leftPadding: 15
    rightPadding: 15

    background: Rectangle {
        radius: 10
        color: control.tone === "primary"
            ? (control.down ? "#0A46C8" : control.hovered ? control.theme.accentHover : control.theme.accent)
            : control.tone === "danger"
                ? (control.hovered ? "#9F1E15" : control.theme.danger)
                : (control.down ? "#EDF1F6" : control.hovered ? control.theme.surfaceHover : control.theme.surface)
        border.width: control.tone === "default" ? 1 : 0
        border.color: control.theme.borderStrong
        Behavior on color { ColorAnimation { duration: 110 } }
    }

    contentItem: Text {
        text: (control.glyph.length > 0 ? control.glyph + "   " : "") + control.text
        color: control.tone === "default" ? control.theme.text : "#FFFFFF"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        opacity: control.enabled ? 1 : 0.45
    }
}
