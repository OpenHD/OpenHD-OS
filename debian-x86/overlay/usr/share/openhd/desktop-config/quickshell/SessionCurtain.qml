import QtQuick

Rectangle {
    id: curtain
    property real coverage: 0
    property url wordmark: "file:///usr/share/openhd/brand/apps/qopenhd-wordmark.png"

    color: "black"
    opacity: coverage
    visible: coverage > 0

    Image {
        anchors.centerIn: parent
        source: curtain.wordmark
        width: 200
        height: 56
        fillMode: Image.PreserveAspectFit
        opacity: (1 - Math.abs(curtain.coverage * 2 - 1)) * 0.9
        smooth: true
    }
}
