cmake_minimum_required(VERSION 3.20)

find_package(Qt6 REQUIRED COMPONENTS Quick)

qt_standard_project_setup()

qt_add_executable(haskell-qt
    main.cpp
    backend.cpp
    backend.h
)

target_link_libraries(haskell-qt PRIVATE Qt6::Quick)
target_compile_definitions(haskell-qt PRIVATE QML_DIR="${CMAKE_SOURCE_DIR}/qml")
target_include_directories(haskell-qt PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

set_target_properties(haskell-qt PROPERTIES AUTOMOC ON)

# Ensure Haskell is built first, then copy binary next to Qt executable
add_dependencies(haskell-qt build-haskell)

add_custom_command(
    TARGET haskell-qt POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${HASKELL_BIN}
        $<TARGET_FILE_DIR:haskell-qt>/haskell-backend
    COMMENT "Copying Haskell binary next to Qt executable"
)
