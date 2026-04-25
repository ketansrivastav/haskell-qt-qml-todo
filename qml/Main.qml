import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.Universal 2.2

ApplicationWindow {
    id: mainWindow
    width: 1100
    height: 900
    title: "Monadic State Todo App"
    visible: true
    Universal.theme: Universal.Light

    // ── Global selection state (single source of truth) ────────
    property int selectedProjectId: 0   // 0 = "All"

    // Sidebar list = virtual "All" row + real projects from backend
    property var sidebarItems: {
        var items = [{ projectId: 0, projectName: "All Todos", iconText: "☰" }]
        var projects = backend.state.projects || []
        for (var i = 0; i < projects.length; i++) {
            items.push({
                projectId:   projects[i].projectId,
                projectName: projects[i].projectName,
                iconText:    "📁"
            })
        }
        return items
    }

    // Filtered todos for the active project (0 = all)
    property var visibleTodos: selectedProjectId === 0
        ? (backend.state.todos || [])
        : (backend.state.todos || []).filter(function(t) {
            return t.todoProjectId === selectedProjectId
        })

    // ── Root layout: sidebar | content ─────────────────────────
    // SplitView gives a free draggable divider between panes.
    SplitView {
        anchors.fill: parent
        orientation:  Qt.Horizontal

        // ── Sidebar ────────────────────────────────────────────
        Rectangle {
            SplitView.preferredWidth: 220
            SplitView.minimumWidth:   160
            SplitView.maximumWidth:   300

            color:        "#fafafa"
            border.color: "#e8e8e8"
            border.width: 1

            ColumnLayout {
                anchors.fill:    parent
                anchors.margins: 12
                spacing:         4

                Text {
                    text:           "Projects"
                    font.pixelSize: 11
                    font.weight:    Font.Medium
                    color:          "#999"
                    topPadding:     4
                    bottomPadding:  8
                    leftPadding:    6
                }

                // ListView virtualizes — only visible delegates are
                // instantiated. Critical for large project lists.
                ListView {
                    id:               projectList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip:             true
                    spacing:          2
                    model:            mainWindow.sidebarItems

                    delegate: SidebarItem {
                        label:      modelData.projectName
                        iconText:   modelData.iconText
                        count:      modelData.projectId === 0
                                        ? (backend.state.todos || []).length
                                        : (backend.state.todos || []).filter(function(t) {
                                              return t.todoProjectId === modelData.projectId
                                          }).length
                        selected:   modelData.projectId === mainWindow.selectedProjectId
                        onClicked:  mainWindow.selectedProjectId = modelData.projectId
                    }

                    // Smooth scrolling
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }

                // Sidebar footer — e.g. add project button
                Rectangle {
                    Layout.fillWidth: true
                    height:           36
                    radius:           6
                    color:            addHover.containsMouse ? "#f0f0f0" : "transparent"

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill:        parent
                        anchors.leftMargin:  10
                        anchors.rightMargin: 10
                        spacing:             8

                        Text {
                            text:           "+"
                            font.pixelSize: 18
                            color:          "#aaa"
                        }
                        Text {
                            text:           "New project"
                            font.pixelSize: 13
                            color:          "#aaa"
                        }
                    }

                    MouseArea {
                        id:           addHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    backend.addProject("New Project")
                    }
                }
            }
        }

        // ── Main content ───────────────────────────────────────
        ColumnLayout {
            SplitView.fillWidth: true
            spacing:             15

            // Top padding/margin via a container
            Item {
                Layout.fillWidth:  true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill:    parent
                    anchors.margins: 20
                    spacing:         15

                    // Header: shows active project name
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            property string projectName: {
                                if (mainWindow.selectedProjectId === 0) return "All Todos"
                                var ps = backend.state.projects || []
                                for (var i = 0; i < ps.length; i++)
                                    if (ps[i].projectId === mainWindow.selectedProjectId)
                                        return ps[i].projectName
                                return "All Todos"
                            }

                            text:           projectName
                            font.bold:      true
                            font.pixelSize: 20
                            color:          "#1a1a2e"
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text:           mainWindow.visibleTodos.length + " items"
                            font.pixelSize: 13
                            color:          "#aaa"
                        }
                    }

                    // Input row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing:          10

                        TextField {
                            id:               todoInput
                            Layout.fillWidth: true
                            placeholderText:  "Add a new todo..."
                            onAccepted: {
                                if (text.trim() !== "" && backend) {
                                    backend.addTodo(text, mainWindow.selectedProjectId)
                                    text = ""
                                }
                            }
                        }

                        Button {
                            text: "Add"
                            onClicked: {
                                if (todoInput.text.trim() !== "" && backend) {
                                    backend.addTodo(todoInput.text, mainWindow.selectedProjectId)
                                    todoInput.text = ""
                                }
                            }
                        }

                        Button {
                            text: backend.state.isAscending ? "↑" : "↓"
                            onClicked: {
                                if (backend.state.isAscending)
                                    backend.sortDescending()
                                else
                                    backend.sortAscending()
                            }
                        }

                        TextField {
                            id:               filterText
                            Layout.fillWidth: true
                            placeholderText:  "Search..."
                            onTextChanged: {
                                if (backend) backend.setFilterText(filterText.text)
                            }
                        }
                    }

                    // Todo cards
                    ScrollView {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        clip:              true
                        contentWidth:      availableWidth

                        Flow {
                            width:   parent.width
                            spacing: 10

                            Repeater {
                                model: mainWindow.visibleTodos

                                TodoCard {
                                    todoId:      modelData.todoId
                                    title:       modelData.title
                                    done:        modelData.done
                                    description: modelData.description ?? ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
