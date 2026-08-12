import QtQuick

QtObject {
    readonly property color canvas: "#F4F7FB"
    readonly property color canvasAlt: "#EEF3F9"
    readonly property color surface: "#FFFFFF"
    readonly property color surfaceRaised: "#FCFDFE"
    readonly property color surfaceSoft: "#F7F9FC"
    readonly property color surfaceHover: "#F1F5FB"
    readonly property color border: "#E1E7EF"
    readonly property color borderStrong: "#D3DCE8"
    readonly property color textStrong: "#111827"
    readonly property color text: "#273449"
    readonly property color textMuted: "#68758A"
    readonly property color textFaint: "#98A3B3"
    readonly property color accent: "#155EEF"
    readonly property color accentHover: "#0B4FDB"
    readonly property color accentSoft: "#EAF1FF"
    readonly property color accentSoftStrong: "#DCE8FF"
    readonly property color success: "#147A55"
    readonly property color successSoft: "#EAF8F1"
    readonly property color warning: "#A65A08"
    readonly property color warningSoft: "#FFF5E8"
    readonly property color danger: "#B42318"
    readonly property color dangerSoft: "#FFF0EE"
    readonly property color infoSoft: "#EFF6FF"
    readonly property color shadow: "#140D1726"

    readonly property int radiusSmall: 10
    readonly property int radiusMedium: 14
    readonly property int radiusLarge: 18
    readonly property int radiusXL: 24
    readonly property int space1: 6
    readonly property int space2: 10
    readonly property int space3: 14
    readonly property int space4: 18
    readonly property int space5: 24
    readonly property int space6: 30

    function toneBackground(tone) {
        if (tone === "good") return successSoft
        if (tone === "warn") return warningSoft
        if (tone === "danger") return dangerSoft
        if (tone === "accent") return accentSoft
        return surfaceSoft
    }

    function toneForeground(tone) {
        if (tone === "good") return success
        if (tone === "warn") return warning
        if (tone === "danger") return danger
        if (tone === "accent") return accent
        return textMuted
    }

    function toneBorder(tone) {
        if (tone === "good") return "#CDEDDD"
        if (tone === "warn") return "#F0D5AD"
        if (tone === "danger") return "#F0C5C0"
        if (tone === "accent") return "#CADBFF"
        return border
    }
}
