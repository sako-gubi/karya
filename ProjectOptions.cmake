include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(karya_supports_sanitizers)
  # Emscripten doesn't support sanitizers
  if(EMSCRIPTEN)
    set(SUPPORTS_UBSAN OFF)
    set(SUPPORTS_ASAN OFF)
  elseif((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(karya_setup_options)
  option(karya_ENABLE_HARDENING "Enable hardening" ON)
  option(karya_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    karya_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    karya_ENABLE_HARDENING
    OFF)

  karya_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR karya_PACKAGING_MAINTAINER_MODE)
    option(karya_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(karya_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(karya_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(karya_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(karya_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(karya_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(karya_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(karya_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(karya_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(karya_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(karya_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(karya_ENABLE_PCH "Enable precompiled headers" OFF)
    option(karya_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(karya_ENABLE_IPO "Enable IPO/LTO" ON)
    option(karya_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(karya_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(karya_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(karya_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(karya_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(karya_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(karya_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(karya_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(karya_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(karya_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(karya_ENABLE_PCH "Enable precompiled headers" OFF)
    option(karya_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      karya_ENABLE_IPO
      karya_WARNINGS_AS_ERRORS
      karya_ENABLE_USER_LINKER
      karya_ENABLE_SANITIZER_ADDRESS
      karya_ENABLE_SANITIZER_LEAK
      karya_ENABLE_SANITIZER_UNDEFINED
      karya_ENABLE_SANITIZER_THREAD
      karya_ENABLE_SANITIZER_MEMORY
      karya_ENABLE_UNITY_BUILD
      karya_ENABLE_CLANG_TIDY
      karya_ENABLE_CPPCHECK
      karya_ENABLE_COVERAGE
      karya_ENABLE_PCH
      karya_ENABLE_CACHE)
  endif()

  karya_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (karya_ENABLE_SANITIZER_ADDRESS OR karya_ENABLE_SANITIZER_THREAD OR karya_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(karya_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(karya_global_options)
  if(karya_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    karya_enable_ipo()
  endif()

  karya_supports_sanitizers()

  if(karya_ENABLE_HARDENING AND karya_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR karya_ENABLE_SANITIZER_UNDEFINED
       OR karya_ENABLE_SANITIZER_ADDRESS
       OR karya_ENABLE_SANITIZER_THREAD
       OR karya_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${karya_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${karya_ENABLE_SANITIZER_UNDEFINED}")
    karya_enable_hardening(karya_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(karya_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(karya_warnings INTERFACE)
  add_library(karya_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  karya_set_project_warnings(
    karya_warnings
    ${karya_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  # Linker and sanitizers not supported in Emscripten
  if(NOT EMSCRIPTEN)
    if(karya_ENABLE_USER_LINKER)
      include(cmake/Linker.cmake)
      karya_configure_linker(karya_options)
    endif()

    include(cmake/Sanitizers.cmake)
    karya_enable_sanitizers(
      karya_options
      ${karya_ENABLE_SANITIZER_ADDRESS}
      ${karya_ENABLE_SANITIZER_LEAK}
      ${karya_ENABLE_SANITIZER_UNDEFINED}
      ${karya_ENABLE_SANITIZER_THREAD}
      ${karya_ENABLE_SANITIZER_MEMORY})
  endif()

  set_target_properties(karya_options PROPERTIES UNITY_BUILD ${karya_ENABLE_UNITY_BUILD})

  if(karya_ENABLE_PCH)
    target_precompile_headers(
      karya_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(karya_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    karya_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(karya_ENABLE_CLANG_TIDY)
    karya_enable_clang_tidy(karya_options ${karya_WARNINGS_AS_ERRORS})
  endif()

  if(karya_ENABLE_CPPCHECK)
    karya_enable_cppcheck(${karya_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(karya_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    karya_enable_coverage(karya_options)
  endif()

  if(karya_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(karya_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(karya_ENABLE_HARDENING AND NOT karya_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR karya_ENABLE_SANITIZER_UNDEFINED
       OR karya_ENABLE_SANITIZER_ADDRESS
       OR karya_ENABLE_SANITIZER_THREAD
       OR karya_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    karya_enable_hardening(karya_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
