#!/bin/bash
# Quick build and flash script for Voice Lock System

set -e

echo "=== Voice Lock System Build Script ==="

# Check if ESP-IDF is sourced
if [ -z "$IDF_PATH" ] || [ ! -d "$IDF_PATH" ]; then
    echo "ERROR: ESP-IDF not found. Please source export.sh first:"
    echo "  sh -c '. ~/src/vscode/pi/LockWise/embedded/esp-adf/export.sh && ./build.sh <command>'"
    exit 1
fi

# Check if ESP-ADF is set
if [ -z "$ADF_PATH" ] || [ ! -d "$ADF_PATH" ]; then
    echo "ERROR: ADF_PATH not set properly. Please source export.sh first:"
    echo "  sh -c '. ~/src/vscode/pi/LockWise/embedded/esp-adf/export.sh && ./build.sh <command>'"
    exit 1
fi

# Validate paths
if [ ! -d "$IDF_PATH/components" ]; then
    echo "ERROR: IDF_PATH ($IDF_PATH) does not contain ESP-IDF"
    exit 1
fi

if [ ! -d "$ADF_PATH/components" ]; then
    echo "ERROR: ADF_PATH ($ADF_PATH) does not contain ESP-ADF"
    exit 1
fi

echo "ESP-IDF Path: $IDF_PATH"
echo "ESP-ADF Path: $ADF_PATH"
echo ""

# Function to manage MQTT TLS certificates
manage_mqtt_certs() {
    echo "=== Checking MQTT TLS Configuration ==="

    # Read MQTT broker URL from sdkconfig
    MQTT_BROKER_URL=""
    if [ -f sdkconfig ]; then
        MQTT_BROKER_URL=$(grep "^CONFIG_MQTT_BROKER_URL=" sdkconfig | cut -d'"' -f2)
    fi

    if [ -z "$MQTT_BROKER_URL" ]; then
        echo "No MQTT broker configured, skipping certificate management"
        return 0
    fi

    echo "MQTT Broker: $MQTT_BROKER_URL"

    # Check if using mqtts://
    if [[ ! "$MQTT_BROKER_URL" =~ ^mqtts:// ]]; then
        echo "MQTT broker is not using TLS (mqtts://), skipping certificate management"
        # Ensure SSL is disabled in sdkconfig.defaults
        sed -i 's/CONFIG_MQTT_TRANSPORT_SSL=y/CONFIG_MQTT_TRANSPORT_SSL=n/' sdkconfig.defaults 2>/dev/null || true
        return 0
    fi

    # Extract hostname and port from mqtts://hostname:port
    MQTT_HOST=$(echo "$MQTT_BROKER_URL" | sed -E 's|^mqtts://([^:]+).*|\1|')
    MQTT_PORT=$(echo "$MQTT_BROKER_URL" | sed -E 's|^mqtts://[^:]+:([0-9]+).*|\1|')

    # Default to 8883 if no port specified
    if [ "$MQTT_PORT" = "$MQTT_BROKER_URL" ]; then
        MQTT_PORT="8883"
    fi

    echo "Hostname: $MQTT_HOST"
    echo "Port: $MQTT_PORT"

    # Create certs directory
    mkdir -p main/certs

    CERT_FILE="main/certs/mqtt_ca.pem"
    CERT_AGE_DAYS=3
    NEED_DOWNLOAD=false

    # Check if certificate exists and age
    if [ -f "$CERT_FILE" ]; then
        CERT_AGE=$(( ($(date +%s) - $(stat -c %Y "$CERT_FILE" 2>/dev/null || stat -f %m "$CERT_FILE")) / 86400 ))
        echo "Certificate found, age: $CERT_AGE days"

        if [ $CERT_AGE -gt $CERT_AGE_DAYS ]; then
            echo "Certificate is older than $CERT_AGE_DAYS days, will re-download"
            NEED_DOWNLOAD=true
        else
            echo "Certificate is recent, skipping download"
        fi
    else
        echo "Certificate not found, will download"
        NEED_DOWNLOAD=true
    fi

    # Download certificate if needed
    if [ "$NEED_DOWNLOAD" = true ]; then
        echo "Downloading certificate chain from $MQTT_HOST:$MQTT_PORT..."

        # Use openssl to get the certificate chain
        TEMP_CERT=$(mktemp)
        if ! openssl s_client -showcerts -connect "$MQTT_HOST:$MQTT_PORT" -servername "$MQTT_HOST" </dev/null 2>/dev/null | \
            sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > "$TEMP_CERT"; then
            echo "ERROR: Failed to download certificate from $MQTT_HOST:$MQTT_PORT"
            rm -f "$TEMP_CERT"
            return 1
        fi

        # Verify the certificate is valid
        if ! openssl x509 -in "$TEMP_CERT" -text -noout > /dev/null 2>&1; then
            echo "ERROR: Downloaded certificate is invalid"
            rm -f "$TEMP_CERT"
            return 1
        fi

        # Verify the certificate chain
        echo "Validating certificate chain..."
        if ! openssl s_client -connect "$MQTT_HOST:$MQTT_PORT" -servername "$MQTT_HOST" -CAfile "$TEMP_CERT" </dev/null 2>&1 | grep -q "Verify return code: 0"; then
            echo "WARNING: Certificate chain validation returned non-zero (this may be OK if using self-signed certs)"
        else
            echo "Certificate chain validated successfully"
        fi

        # Move to final location
        mv "$TEMP_CERT" "$CERT_FILE"
        echo "Certificate saved to $CERT_FILE"

        # Show certificate info
        echo ""
        echo "Certificate details:"
        openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates | sed 's/^/  /'
        echo ""
    fi

    # Ensure SSL is enabled in sdkconfig.defaults
    if grep -q "CONFIG_MQTT_TRANSPORT_SSL=n" sdkconfig.defaults; then
        echo "Enabling MQTT SSL in sdkconfig.defaults..."
        sed -i 's/CONFIG_MQTT_TRANSPORT_SSL=n/CONFIG_MQTT_TRANSPORT_SSL=y/' sdkconfig.defaults
    elif ! grep -q "CONFIG_MQTT_TRANSPORT_SSL" sdkconfig.defaults; then
        echo "Adding MQTT SSL config to sdkconfig.defaults..."
        sed -i '/# MQTT Configuration/a CONFIG_MQTT_TRANSPORT_SSL=y' sdkconfig.defaults
    fi

    # Also update sdkconfig directly if it exists
    if [ -f sdkconfig ]; then
        if grep -q "# CONFIG_MQTT_TRANSPORT_SSL is not set" sdkconfig; then
            echo "Enabling MQTT SSL in sdkconfig..."
            sed -i 's/# CONFIG_MQTT_TRANSPORT_SSL is not set/CONFIG_MQTT_TRANSPORT_SSL=y/' sdkconfig
        elif ! grep -q "CONFIG_MQTT_TRANSPORT_SSL=y" sdkconfig; then
            echo "Adding MQTT SSL to sdkconfig..."
            sed -i '/# MQTT Configuration/a CONFIG_MQTT_TRANSPORT_SSL=y' sdkconfig
        fi
    fi

    echo "MQTT TLS configuration complete"
    echo ""
}

# Run certificate management before build
manage_mqtt_certs

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
