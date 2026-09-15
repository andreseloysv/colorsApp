# CMake del motor de color (capas 1 y 2). Compila en nativo (clang) y con
# Emscripten (emcmake cmake ...). En WASM los ejecutables salen como .js y ctest
# los corre con node (CMAKE_CROSSCOMPILING_EMULATOR lo fija el toolchain de
# Emscripten).
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
  Sources/CColorEngine/ce_dict.c
  Sources/CColorEngine/ce_ctx.c
  Sources/CColorEngine/ce_image.c
  Sources/CColorEngine/ce_palette.c)
target_include_directories(colorengine PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/Sources/CColorEngine/include>)
target_compile_options(colorengine PRIVATE ${CE_STRICT_FLAGS})
if(UNIX AND NOT APPLE)
  target_link_libraries(colorengine PUBLIC m)
endif()

# ---- CLI ------------------------------------------------------------------
if(CE_BUILD_CLI)
  # ce_pnm.c (parser P6/P5, entrada no confiable) vive en tools/, fuera del
  # target SPM; lo comparten el CLI y el fuzz loop.
  add_executable(ce tools/ce_cli.c tools/ce_pnm.c)
  target_include_directories(ce PRIVATE tools)
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
  # ---- capa 2 -------------------------------------------------------------
  # Directorio de salida de los fixtures que escribe test_palette (PPM/PGM
  # sintéticos) y que consumen los tests del CLI.
  set(CE_TEST_OUT_DIR "${CMAKE_BINARY_DIR}/testout")
  file(MAKE_DIRECTORY "${CE_TEST_OUT_DIR}")

  # Contexto: presupuesto (<= 2 MiB), alineación, validación de imagen y opciones.
  add_executable(test_ctx tests/test_ctx.c)
  target_link_libraries(test_ctx PRIVATE colorengine unity)
  target_compile_options(test_ctx PRIVATE ${CE_STRICT_FLAGS})
  if(EMSCRIPTEN)
    target_link_options(test_ctx PRIVATE -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
    add_test(NAME test_ctx COMMAND ${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:test_ctx>)
  else()
    add_test(NAME test_ctx COMMAND test_ctx)
  endif()
  set_tests_properties(test_ctx PROPERTIES TIMEOUT 120)

  # Paleta: composiciones sintéticas, invariancias, máscara, formatos/stride,
  # parser PNM y rendimiento (1024x1024 RGBA). Compila también ce_pnm.c.
  add_executable(test_palette tests/test_palette.c tools/ce_pnm.c)
  target_include_directories(test_palette PRIVATE tools)
  target_link_libraries(test_palette PRIVATE colorengine unity)
  target_compile_options(test_palette PRIVATE ${CE_STRICT_FLAGS})
  target_compile_definitions(test_palette PRIVATE CE_TEST_OUT_DIR="${CE_TEST_OUT_DIR}")
  # La cota de 150 ms solo se exige en nativo -O2 sin sanitizers; en ASan y
  # WASM se mide e imprime.
  if(NOT EMSCRIPTEN AND NOT CE_SANITIZE)
    target_compile_definitions(test_palette PRIVATE CE_PERF_GATE_MS=150)
  endif()
  if(EMSCRIPTEN)
    target_link_options(test_palette PRIVATE -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
    add_test(NAME test_palette COMMAND ${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:test_palette>)
  else()
    add_test(NAME test_palette COMMAND test_palette)
  endif()
  set_tests_properties(test_palette PROPERTIES TIMEOUT 600 FIXTURES_SETUP palette_fixtures)

  # Fuzz loop propio (Apple clang no trae libFuzzer): PRNG xorshift64* con
  # semilla, ce_palette_extract + ce_pnm_parse. `make fuzz` lo ejecuta 600 s
  # bajo ASan/UBSan; aquí solo un humo de 2 s para que ctest lo compile y lo
  # ejercite en cada build (nativo, ASan y WASM).
  add_executable(fuzz_palette tests/fuzz_palette.c tools/ce_pnm.c)
  target_include_directories(fuzz_palette PRIVATE tools)
  target_link_libraries(fuzz_palette PRIVATE colorengine)
  target_compile_options(fuzz_palette PRIVATE ${CE_STRICT_FLAGS})
  if(EMSCRIPTEN)
    target_link_options(fuzz_palette PRIVATE -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
    add_test(NAME fuzz_smoke COMMAND ${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:fuzz_palette> 1 2)
  else()
    add_test(NAME fuzz_smoke COMMAND fuzz_palette 1 2)
  endif()
  set_tests_properties(fuzz_smoke PROPERTIES TIMEOUT 120)

  # CLI de extremo a extremo sobre los fixtures de test_palette: JSON válido con
  # "hash" (exit 0) y fichero truncado -> exit 2 exactamente.
  if(CE_BUILD_CLI)
    add_test(NAME cli_palette_json
      COMMAND sh -c "${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:ce> palette ${CE_TEST_OUT_DIR}/palette_3blocks.ppm --mask ${CE_TEST_OUT_DIR}/palette_mask.pgm --center-sigma 0 --json | grep -Eq '\"hash\": \"[0-9a-f]{16}\"'")
    add_test(NAME cli_palette_truncated
      COMMAND sh -c "${CMAKE_CROSSCOMPILING_EMULATOR} $<TARGET_FILE:ce> palette ${CE_TEST_OUT_DIR}/palette_truncated.ppm --json >/dev/null 2>&1; test $? -eq 2")
    set_tests_properties(cli_palette_json cli_palette_truncated PROPERTIES
      FIXTURES_REQUIRED palette_fixtures TIMEOUT 60)
  endif()
endif()
