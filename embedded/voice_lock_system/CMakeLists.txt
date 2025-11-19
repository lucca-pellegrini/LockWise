# The following lines of boilerplate have to be in your project's CMakeLists
# in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.5)

# Add ADF_PATH environment variable
set(ADF_PATH $ENV{ADF_PATH})

# Include ADF components
set(EXTRA_COMPONENT_DIRS 
    ${ADF_PATH}/components/audio_pipeline
    ${ADF_PATH}/components/audio_sal
    ${ADF_PATH}/components/audio_stream
    ${ADF_PATH}/components/audio_hal
    ${ADF_PATH}/components/audio_board
    ${ADF_PATH}/components/esp_peripherals
    ${ADF_PATH}/components/esp_codec_dev
)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(voice_lock_system)
