cmake_minimum_required(VERSION 3.18)
project(swdecode C CXX)

# FFmpeg decode-only static libs, one folder per ABI, produced by scripts/build_ffmpeg.sh.
# Without them the module still builds as a stub (software decoding is then simply unavailable).
set(FF ${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/${ANDROID_ABI})

add_library(swdecode SHARED swdecode.cpp)
target_compile_options(swdecode PRIVATE -O3 -fvisibility=hidden -ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.)
target_link_libraries(swdecode android log m)
# Reproducible builds: no build-id (it hashes the unstripped binary and embeds the NDK path).
target_link_options(swdecode PRIVATE -Wl,--build-id=none -Wl,-Bsymbolic -Wl,--exclude-libs,ALL -Wl,-z,max-page-size=16384)

if(EXISTS ${FF}/lib/libavcodec.a AND EXISTS ${FF}/lib/libavutil.a)
  add_library(avcodec STATIC IMPORTED)
  set_target_properties(avcodec PROPERTIES IMPORTED_LOCATION ${FF}/lib/libavcodec.a)
  add_library(avutil STATIC IMPORTED)
  set_target_properties(avutil PROPERTIES IMPORTED_LOCATION ${FF}/lib/libavutil.a)
  target_include_directories(swdecode PRIVATE ${FF}/include)
  target_compile_definitions(swdecode PRIVATE HAVE_FFMPEG=1)
  target_link_libraries(swdecode avcodec avutil)
else()
  message(WARNING "FFmpeg libs not found for ${ANDROID_ABI}: building the software-decoder stub")
endif()
