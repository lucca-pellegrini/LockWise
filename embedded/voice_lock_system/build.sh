#!/bin/bash
# Quick build and flash script for Voice Lock System

set -e

echo "=== Voice Lock System Build Script ==="

# Check if ESP-IDF is sourced
if [ -z "$IDF_PATH" ]; then
    echo "ERROR: ESP-IDF not found. Please source export.sh first:"
    echo "  cd /path/to/esp-idf"
    echo "  . ./export.sh"
    exit 1
fi

# Check if ESP-ADF is set
if [ -z "$ADF_PATH" ]; then
    echo "WARNING: ADF_PATH not set. Setting to default..."
    export ADF_PATH="/home/luc/src/vscode/pi/LockWise/embedded/esp-adf"
    if [ ! -d "$ADF_PATH" ]; then
        echo "ERROR: ESP-ADF not found at $ADF_PATH"
        exit 1
    fi
fi

echo "ESP-IDF Path: $IDF_PATH"
echo "ESP-ADF Path: $ADF_PATH"
echo ""

# Parse command line arguments
ACTION=${1:-build}
PORT=${2:-/dev/ttyUSB0}

case $ACTION in
    menuconfig)
        echo "Opening menuconfig..."
        idf.py menuconfig
        ;;
    build)
        echo "Building project..."
        idf.py build
        echo ""
        echo "Build complete! To flash, run:"
        echo "  ./build.sh flash $PORT"
        ;;
    flash)
        echo "Flashing to $PORT..."
        idf.py -p $PORT flash
        echo ""
        echo "Flash complete! To monitor, run:"
        echo "  ./build.sh monitor $PORT"
        ;;
    monitor)
        echo "Starting monitor on $PORT..."
        echo "Press Ctrl+] to exit"
        idf.py -p $PORT monitor
        ;;
    all)
        echo "Building and flashing..."
        idf.py build
        idf.py -p $PORT flash monitor
        ;;
    clean)
        echo "Cleaning build..."
        idf.py fullclean
        ;;
    erase)
        echo "Erasing flash on $PORT..."
        idf.py -p $PORT erase-flash
        ;;
    *)
        echo "Usage: $0 {menuconfig|build|flash|monitor|all|clean|erase} [port]"
        echo ""
        echo "Commands:"
        echo "  menuconfig  - Open configuration menu"
        echo "  build       - Build the project"
        echo "  flash       - Flash to device (default: /dev/ttyUSB0)"
        echo "  monitor     - Start serial monitor"
        echo "  all         - Build, flash, and monitor"
        echo "  clean       - Clean build files"
        echo "  erase       - Erase entire flash"
        echo ""
        echo "Examples:"
        echo "  $0 build"
        echo "  $0 flash /dev/ttyUSB0"
        echo "  $0 all /dev/ttyUSB1"
        exit 1
        ;;
esac
