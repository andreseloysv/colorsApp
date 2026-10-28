# Motor de color para Android: compila directamente las fuentes C11 del repo
# (engine/Sources/CColorEngine/*.c), las mismas que iOS (SwiftPM) y WASM.
# Nada de lógica de color aquí fuera del motor: ce_jni.c solo adapta tipos.
cmake_minimum_required(VERSION 3.22.1)
project(colorengine_android C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Raíz del repo: android/engine/src/main/cpp -> ../../../../..
get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../" ABSOLUTE)
set(CE_DIR "${REPO_ROOT}/engine/Sources/CColorEngine")

set(CE_SOURCES
    "${CE_DIR}/ce_math.c"
    "${CE_DIR}/ce_libm.c"
    "${CE_DIR}/ce_dict.c"
    "${CE_DIR}/ce_ctx.c"
    "${CE_DIR}/ce_image.c"
    "${CE_DIR}/ce_palette.c"
    "${CE_DIR}/ce_match.c"
    "${CE_DIR}/ce_mask.c"
    "${CE_DIR}/ce_garment.c"
    "${CE_DIR}/ce_debug.c"
)

# Los mismos flags estrictos que engine/CMakeLists.txt (CE_STRICT_FLAGS).
# NUNCA -ffast-math / -Ofast / -ffp-contract=fast: la paridad bit a bit con
# iOS/WASM depende de -ffp-contract=off y de la libm propia (ce_libm.c).
set(CE_STRICT_FLAGS -Wall -Wextra -Werror -Wpedantic -ffp-contract=off)

add_library(colorengine SHARED ${CE_SOURCES} ce_jni.c)
target_include_directories(colorengine PRIVATE "${CE_DIR}/include" "${CE_DIR}")
target_compile_options(colorengine PRIVATE ${CE_STRICT_FLAGS})
target_link_libraries(colorengine PRIVATE m log)
