# Quick Start Guide

## Initial Setup (First Time Only)

### 1. Install Dependencies

```bash
# Install required packages (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install git wget flex bison gperf python3 python3-pip \
    python3-setuptools cmake ninja-build ccache libffi-dev libssl-dev \
    dfu-util libusb-1.0-0
```

### 2. Setup ESP-IDF

```bash
# Clone ESP-IDF v5.2
cd ~/esp
git clone -b v5.2 --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32

# Source the environment (do this every time you open a new terminal)
. ./export.sh
```

### 3. Setup ESP-ADF

```bash
# Navigate to your project directory
cd /home/luc/src/vscode/pi/LockWise/embedded

# Clone ESP-ADF if not already done
git clone --recursive https://github.com/espressif/esp-adf.git
cd esp-adf
./install.sh

# Set ADF_PATH (do this every time you open a new terminal)
export ADF_PATH=$(pwd)
```

## Daily Workflow

### Every Terminal Session

```bash
# Source ESP-IDF
cd ~/esp/esp-idf
. ./export.sh

# Set ADF_PATH
export ADF_PATH=/home/luc/src/vscode/pi/LockWise/embedded/esp-adf

# Navigate to project
cd /home/luc/src/vscode/pi/LockWise/embedded/voice_lock_system
```

### Configure Project (First Time)

```bash
# Run menuconfig to set WiFi credentials and other settings
./build.sh menuconfig

# Navigate to: Voice Lock Configuration
# Set:
#   - WiFi SSID
#   - WiFi Password
#   - Device ID
#   - Backend URL
#   - MQTT Broker URL
# Save and exit (press 'S', then 'Q')
```

### Build and Flash

```bash
# Build only
./build.sh build

# Flash to device (make sure ESP32 is connected via USB)
./build.sh flash

# Flash and monitor
./build.sh all

# Just monitor serial output
./build.sh monitor
```

## Common Issues

### Permission Denied on /dev/ttyUSB0

```bash
# Add your user to dialout group
sudo usermod -a -G dialout $USER

# Log out and log back in, or run:
newgrp dialout
```

### ESP32 Not Detected

```bash
# Check if device is connected
ls -l /dev/ttyUSB*

# If nothing shows, try:
ls -l /dev/ttyACM*

# Install CH340 drivers if needed (for some ESP32 boards)
sudo apt-get install linux-headers-$(uname -r)
```

### Build Errors

```bash
# Clean and rebuild
./build.sh clean
./build.sh build

# If still failing, check:
# 1. ESP-IDF is sourced: echo $IDF_PATH
# 2. ADF_PATH is set: echo $ADF_PATH
# 3. All submodules are initialized: cd $ADF_PATH && git submodule update --init --recursive
```

## Testing Components

### Test WiFi Connection Only

Modify `voice_lock_main.c` temporarily:

```c
void app_main(void)
{
    // Initialize NVS and WiFi
    nvs_flash_init();
    esp_netif_init();
    load_config_from_nvs();
    wifi_init();
    
    ESP_LOGI(TAG, "WiFi connected! System ready.");
    
    // Comment out other initialization for now
    // mqtt_init();
    // audio_pipeline_init();
    
    while(1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
```

### Test MQTT Connection

After confirming WiFi works, uncomment MQTT:

```c
mqtt_init();

// Wait and check MQTT logs
```

### Test Audio Recording

Once WiFi and MQTT are working, test audio:

```c
audio_pipeline_init();

// Trigger a test recording manually
if (start_voice_recording() == ESP_OK) {
    ESP_LOGI(TAG, "Recorded %d bytes", audio_buffer_len);
}
```

## Backend API Development

### Simple Test Backend (Python Flask)

```python
from flask import Flask, request, jsonify
import os

app = Flask(__name__)

@app.route('/api/verify-voice', methods=['POST'])
def verify_voice():
    device_id = request.headers.get('X-Device-ID')
    audio_data = request.get_data()
    
    print(f"Received {len(audio_data)} bytes from device {device_id}")
    
    # TODO: Implement actual voice verification
    # For now, always return verified for testing
    
    return jsonify({
        "verified": True,
        "user_id": "test_user",
        "confidence": 0.95
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

Run with: `python3 backend.py`

## MQTT Broker Setup

### Using Mosquitto (Local Testing)

```bash
# Install Mosquitto
sudo apt-get install mosquitto mosquitto-clients

# Start broker
sudo systemctl start mosquitto

# Test publish (from another terminal)
mosquitto_pub -h localhost -t "lockwise/lockwise_device_001/control" -m "UNLOCK"

# Test subscribe (watch for device status)
mosquitto_sub -h localhost -t "lockwise/lockwise_device_001/status"
```

## Project Structure Overview

```
voice_lock_system/
├── main/
│   ├── voice_lock_main.c       # All application logic
│   ├── CMakeLists.txt          # Component build config
│   └── Kconfig.projbuild       # Configuration menu
├── CMakeLists.txt              # Project build config
├── partitions.csv              # Flash memory partitions
├── sdkconfig.defaults          # Default configurations
├── build.sh                    # Build helper script
├── README.md                   # Full documentation
└── QUICKSTART.md               # This file
```

## Next Steps

1. ✅ Install ESP-IDF and ESP-ADF
2. ✅ Build and flash the project
3. ⬜ Test WiFi connection
4. ⬜ Setup MQTT broker
5. ⬜ Test MQTT commands
6. ⬜ Setup backend API
7. ⬜ Test voice recording
8. ⬜ Wire lock mechanism
9. ⬜ Implement wake word detection
10. ⬜ Add NFC support

## Need Help?

- ESP-IDF Docs: https://docs.espressif.com/projects/esp-idf/en/latest/
- ESP-ADF Docs: https://docs.espressif.com/projects/esp-adf/en/latest/
- ESP32 Forum: https://esp32.com/

Good luck with your project! 🔐
