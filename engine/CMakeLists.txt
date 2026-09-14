# CMake del motor de color (capa 1). Compila en nativo (clang) y con Emscripten
# (emcmake cmake ...). En WASM los ejecutables salen como .js y ctest los corre
# con node (CMAKE_CROSSCOMPILING_EMULATOR lo fija el toolchain de Emscripten).
cmake_minimum_required(VERSION 3.20)

project(colorengine LANGUAGES C)

option(CE_BUILD_TESTS "Compilar los tests (ctest)" ON)
option(CE_BUILD_CLI "Compilar el CLI 'ce'" ON)
option(CE_SANITIZE "Añadir -fsanitize=address,undefined" OFF)
set(CE_ROUNDTRIP_STEP "1" CACHE STRING "Paso del round-trip exhaustivo (1 = 16.7M colores)")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Tipo de build" FORCE)
endif()
# Release a -O2 (no -O3): es el nivel con el que se mide el round-trip.
string(REPLACE "-O3" "-O2" CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE}")

# Flags estrictas del motor. NUNCA -ffast-math / -Ofast / -ffp-contract=fast:
# ignoran el pragma STDC FP_CONTRACT y rompen el determinismo nativo/WASM.
set(CE_STRICT_FLAGS -Wall -Wextra -Werror -Wpedantic -ffp-contract=off)

if(CE_SANITIZE)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

# ---- librería -------------------------------------------------------------
add_library(colorengine STATIC
  Sources/CColorEngine/ce_math.c
  Sources/CColorEngine/ce_dict.c)
target_include_directories(colorengine PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/Sources/CColorEngine/include>)
target_compile_options(colorengine PRIVATE ${CE_STRICT_FLAGS})
if(UNIX AND NOT APPLE)
  target_link_libraries(colorengine PUBLIC m)
endif()

# ---- CLI ------------------------------------------------------------------
if(CE_BUILD_CLI)
  add_executable(ce tools/ce_cli.c)
  target_link_libraries(ce PRIVATE colorengine)
  target_compile_options(ce PRIVATE ${CE_STRICT_FLAGS})
  set_target_properties(ce PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
  if(EMSCRIPTEN)
    target_link_options(ce PRIVATE -sNODERAWFS=1 -sEXIT_RUNTIME=1)
  endif()
endif()

# ---- tests ----------------------------------------------------------------
if(CE_BUILD_TESTS)
  enable_testing()

  # Unity (ThrowTheSwitch, MIT) vendorizado; sin -Werror por ser de terceros.
  add_library(unity STATIC tests/unity/unity.c)
  target_include_directories(unity PUBLIC tests/unity)
  target_compile_definitions(unity PUBLIC
    UNITY_INCLUDE_DOUBLE
    UNITY_DOUBLE_PRECISION=1e-12
    UNITY_SUPPORT_64)

  add_executable(test_math tests/test_math.c)
  target_link_libraries(test_math PRIVATE colorengine unity)
  target_compile_options(test_math PRIVATE ${CE_STRICT_FLAGS})
  target_compile_definitions(test_math PRIVATE
    CE_TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data"
    CE_ROUNDTRIP_STEP=${CE_ROUNDTRIP_STEP})

  if(EMSCRIPTEN)
    # NODERAWFS: fopen() va directo al sistema de ficheros de node (golden files).
    target_link_options(test_math PRIVATE -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
    add_test(NAME test_math COMMAND ${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:test_math>)
  else()
    add_test(NAME test_math COMMAND test_math)
  endif()
  set_tests_properties(test_math PROPERTIES TIMEOUT 900)

  # Diccionario de Wada: invariantes de las tablas y Lab de los 159 colores
  # contra golden_wada_lab.tsv (oráculo Python).
  add_executable(test_dict tests/test_dict.c)
  target_link_libraries(test_dict PRIVATE colorengine unity)
  target_compile_options(test_dict PRIVATE ${CE_STRICT_FLAGS})
  target_compile_definitions(test_dict PRIVATE
    CE_TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data")
  if(EMSCRIPTEN)
    target_link_options(test_dict PRIVATE -sNODERAWFS=1 -sEXIT_RUNTIME=1)
    add_test(NAME test_dict COMMAND ${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:test_dict>)
  else()
    add_test(NAME test_dict COMMAND test_dict)
  endif()
  set_tests_properties(test_dict PROPERTIES TIMEOUT 120)
endif()
