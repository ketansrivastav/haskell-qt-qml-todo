cmake_minimum_required(VERSION 3.20)
project(haskell-qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Haskell backend ---
set(HASKELL_DIR ${CMAKE_SOURCE_DIR}/haskell)
set(HASKELL_BIN ${CMAKE_BINARY_DIR}/haskell-backend-bin CACHE INTERNAL "")

add_custom_target(build-haskell ALL
    COMMAND cabal build exe:haskell-backend
    COMMAND bash ${CMAKE_SOURCE_DIR}/haskell/copy-bin.sh ${HASKELL_BIN}
    WORKING_DIRECTORY ${HASKELL_DIR}
    COMMENT "Building Haskell backend"
)

# --- Qt6 C++ frontend ---
add_subdirectory(cpp)
