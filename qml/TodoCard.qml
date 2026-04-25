import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: card

    property int    todoId:      0
    property string title:       ""
    property bool   done:        false
    property string description: ""

    property bool expanded: false

    readonly property int collapsedHeight: 72
    readonly property int expandedHeight:  140

    width:  260
    height: expanded ? expandedHeight : collapsedHeight
    clip:   true

    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }

    radius:       8
    border.width: hoverArea.containsMouse ? 2 : 1
    border.color: hoverArea.containsMouse ? "#5b9bd5" : (card.done ? "#ddd" : "#ccc")
    color:        card.done
                      ? "#f5f5f5"
                      : hoverArea.containsMouse ? "#f0f6ff" : "#ffffff"

    Behavior on color        { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    // Subtle bottom shadow via a background Rectangle
    Rectangle {
        anchors.fill:          parent
        anchors.topMargin:     3
        anchors.bottomMargin: -3
        z:                    -1
        radius:                card.radius
        color:                 "transparent"
        border.color:          Qt.rgba(0, 0, 0, hoverArea.containsMouse ? 0.12 : 0.06)
        border.width:          1

        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    // Hover tracker — propagates clicks to children
    MouseArea {
        id:                      hoverArea
        anchors.fill:            parent
        hoverEnabled:            true
        propagateComposedEvents: true
        onClicked:               mouse.accepted = false
    }

    ColumnLayout {
        anchors.fill:    parent
        anchors.margins: 10
        spacing:         0

        // ── Top row ─────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing:          4

            CheckBox {
                id:      checkBox
                checked: card.done
                padding: 0
                onClicked: {
                    if (backend) backend.toggleTodo(card.todoId)
                }
            }

            Text {
                Layout.fillWidth: true
                text:             card.title
                font.pixelSize:   13
                font.strikeout:   card.done
                color:            card.done ? "#aaa" : "#222"
                elide:            Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            // Expand / collapse chevron
            Text {
                text:             card.expanded ? "▲" : "▼"
                font.pixelSize:   9
                color:            hoverArea.containsMouse ? "#5b9bd5" : "#bbb"
                verticalAlignment: Text.AlignVCenter

                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    card.expanded = !card.expanded
                }
            }

            // Delete button
            Rectangle {
                width:  22
                height: 22
                radius: 11
                color:  deleteHover.containsMouse ? "#ffeded" : "transparent"

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text:             "×"
                    font.pixelSize:   15
                    color:            deleteHover.containsMouse ? "#d9534f" : "#bbb"

                    Behavior on color { ColorAnimation { duration: 100 } }
                }

                MouseArea {
                    id:          deleteHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        if (backend) backend.deleteTodo(card.todoId)
                    }
                }
            }
        }

        // ── Divider ──────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth:  true
            height:            1
            color:             "#ececec"
            visible:           card.expanded
            opacity:           card.expanded ? 1 : 0
            Layout.topMargin:  6
            Layout.bottomMargin: 6

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // ── Description ──────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            visible:          card.expanded
            opacity:          card.expanded ? 1 : 0
            text:             card.description !== "" ? card.description : "No description."
            color:            "#888"
            font.pixelSize:   12
            wrapMode:         Text.WordWrap

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        Item { Layout.fillHeight: true }
    }
}
