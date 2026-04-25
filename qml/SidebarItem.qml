import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: item

    // ── Public interface ────────────────────────────────────────
    property string label:      ""
    property string iconText:   "●"   // swap for an Image/icon later
    property int    count:      0
    property bool   selected:   false
    signal clicked()

    // ── Geometry ────────────────────────────────────────────────
    width:  ListView.view ? ListView.view.width : 200
    height: 40
    radius: 6

    // ── Visuals ─────────────────────────────────────────────────
    color: "transparent"

    // Hover background (suppressed while selected)
    Rectangle {
        anchors.fill: parent
        radius:       parent.radius
        color:        "#000000"
        opacity:      !item.selected && hoverArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 110 } }
    }

    // Selected background
    Rectangle {
        anchors.fill: parent
        radius:       parent.radius
        color:        "#e8f0fe"
        opacity:      item.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 110 } }
    }

    // Left accent bar when selected
    Rectangle {
        width:   3
        height:  24
        radius:  2
        anchors {
            left:           parent.left
            leftMargin:     3
            verticalCenter: parent.verticalCenter
        }
        color:   "#4a7fc1"
        opacity: item.selected ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 110 } }
    }

    RowLayout {
        anchors {
            fill:           parent
            leftMargin:     14
            rightMargin:    10
            topMargin:      6
            bottomMargin:   6
        }
        spacing: 8

        Text {
            text:          item.iconText
            font.pixelSize: 14
            color:         item.selected           ? "#4a7fc1"
                         : hoverArea.containsMouse ? "#ffffff"
                                                   : "#888"

            Behavior on color { ColorAnimation { duration: 110 } }
        }

        Text {
            Layout.fillWidth: true
            text:             item.label
            font.pixelSize:   13
            font.weight:      item.selected ? Font.Medium : Font.Normal
            color:            item.selected           ? "#1a1a2e"
                            : hoverArea.containsMouse ? "#ffffff"
                                                      : "#444"
            elide:            Text.ElideRight

            Behavior on color { ColorAnimation { duration: 110 } }
        }

        // Badge showing item count
        Rectangle {
            visible:       item.count > 0
            width:         Math.max(20, countLabel.implicitWidth + 8)
            height:        18
            radius:        9
            color:         item.selected ? "#4a7fc1" : "#e0e0e0"

            Behavior on color { ColorAnimation { duration: 110 } }

            Text {
                id:                countLabel
                anchors.centerIn:  parent
                text:              item.count
                font.pixelSize:    10
                color:             item.selected ? "#fff" : "#666"

                Behavior on color { ColorAnimation { duration: 110 } }
            }
        }
    }

    MouseArea {
        id:          hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    item.clicked()
    }
}
