# Voice-Controlled Lock System for ESP32-LyraT v4.3

A smart lock system controlled by voice authentication and MQTT commands, built for ESP32-LyraT v4.3 using ESP-IDF and ESP-ADF.

## Features

- **Voice Authentication**: Records audio samples and verifies them against your backend API
- **MQTT Remote Control**: Unlock/lock via mobile app through MQTT broker
- **Auto-Lock**: Automatically locks after 20 seconds
- **Persistent Storage**: WiFi credentials and device configuration stored in NVS flash
- **Audio Processing**: Utilizes ESP32-LyraT's high-quality microphones with hardware audio codec

## Hardware Requirements

- **ESP32-LyraT v4.3** development board
- **Lock mechanism** (solenoid, servo, or electronic lock)
- **GPIO/I2C control** for lock actuation
- **PN532 NFC module** (optional, for NFC functionality)

## Prerequisites

### 1. Install ESP-IDF

```bash
# Clone ESP-IDF (tested with v5.x)
git clone -b v5.2 --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
```

### 2. Install ESP-ADF

```bash
# From your project root
cd /home/luc/src/vscode/pi/LockWise/embedded
git clone --recursive https://github.com/espressif/esp-adf.git
cd esp-adf
./install.sh
export ADF_PATH=$(pwd)
```

## Project Structure

```
voice_lock_system/
├── main/
│   ├── voice_lock_main.c       # Main application code
│   ├── CMakeLists.txt
│   └── Kconfig.projbuild        # Configuration options
├── CMakeLists.txt
├── partitions.csv               # Partition table
├── sdkconfig.defaults           # Default configurations
└── README.md
```

## Configuration

### 1. Basic Configuration via menuconfig

```bash
cd /home/luc/src/vscode/pi/LockWise/embedded/voice_lock_system
idf.py menuconfig
```

Navigate to **"Voice Lock Configuration"** and set:

- **WiFi SSID**: Your WiFi network name
- **WiFi Password**: Your WiFi password
- **Device ID**: Unique identifier (e.g., `lockwise_device_001`)
- **Backend URL**: Your voice verification API endpoint
- **MQTT Broker URL**: Your MQTT broker address
- **Lock Control GPIO**: GPIO pin for lock control (or -1 if using I2C)

### 2. Runtime Configuration (via NVS)

The device stores configuration in NVS flash. You can update these values programmatically or via a configuration interface:

- `wifi_ssid`: WiFi network name
- `wifi_pass`: WiFi password
- `device_id`: Unique device identifier
- `backend_url`: Backend API URL
- `mqtt_broker`: MQTT broker URL

## Building and Flashing

```bash
# Set target to ESP32
idf.py set-target esp32

# Build the project
idf.py build

# Flash to device (connect via USB)
idf.py -p /dev/ttyUSB0 flash

# Monitor serial output
idf.py -p /dev/ttyUSB0 monitor
```

To exit the serial monitor, press `Ctrl+]`.

## Backend API Requirements

### Voice Verification Endpoint

Your backend should expose an endpoint that accepts audio data and returns verification results:

**Endpoint**: `POST /api/verify-voice`

**Headers**:
- `Content-Type: application/octet-stream`
- `X-Device-ID: <device_id>`

**Body**: Raw audio data (16kHz, 16-bit, mono PCM)

**Response** (JSON):
```json
{
  "verified": true,
  "user_id": "user123",
  "confidence": 0.95
}
```

## MQTT Topics

### Subscribe (Device listens on):
- `lockwise/<device_id>/control`
  - Accepts: `UNLOCK`, `LOCK`

### Publish (Device sends status to):
- `lockwise/<device_id>/status`
  - Sends: `LOCKED`, `UNLOCKED`, `AUTHENTICATING`

## GPIO Pin Configuration

### ESP32-LyraT v4.3 Pin Usage

**Used by Audio System**:
- I2S pins (BCLK, WS, DOUT, DIN) - used by audio codec
- I2C pins (GPIO18, GPIO23) - used for codec control

**Available GPIO Options**:
Since most GPIOs are used, consider:
1. **Using I2C GPIO expander** (e.g., PCF8574, MCP23017) connected to existing I2C bus
2. **Using existing button GPIOs** if not needed (GPIO36, GPIO39)
3. **Using SD card pins** if SD card not needed (GPIO13, GPIO14, GPIO15, GPIO34)

**Recommended Approach**: Use I2C GPIO expander
```c
// In Kconfig.projbuild, set:
// CONFIG_USE_I2C_LOCK=y
// CONFIG_I2C_LOCK_ADDR=0x20
```

## Lock Control Implementation

### Option 1: Direct GPIO (if pin available)

```c
#define LOCK_CONTROL_GPIO 13  // Example

void init_lock_gpio() {
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << LOCK_CONTROL_GPIO),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
    };
    gpio_config(&io_conf);
    gpio_set_level(LOCK_CONTROL_GPIO, 0);  // Start locked
}
```

### Option 2: I2C GPIO Expander

```c
#include "driver/i2c.h"

#define I2C_MASTER_NUM I2C_NUM_0
#define I2C_EXPANDER_ADDR 0x20
#define LOCK_PIN 0  // Pin 0 on expander

void i2c_expander_write_pin(uint8_t pin, uint8_t value) {
    // Read current state
    uint8_t data;
    i2c_master_read_from_device(I2C_MASTER_NUM, I2C_EXPANDER_ADDR, 
                                 &data, 1, pdMS_TO_TICKS(1000));
    
    // Modify pin
    if (value) {
        data |= (1 << pin);
    } else {
        data &= ~(1 << pin);
    }
    
    // Write back
    i2c_master_write_to_device(I2C_MASTER_NUM, I2C_EXPANDER_ADDR,
                                &data, 1, pdMS_TO_TICKS(1000));
}
```

## Wake Word Detection (TODO)

Currently, the system triggers voice recording periodically (for testing). To implement proper wake word detection:

1. Use **ESP-SR** (Speech Recognition) library included in ESP-ADF
2. Enable wake word detection in `voice_recognition_task()`
3. Common wake words: "Hi ESP", "Alexa", or custom wake words

```c
// TODO: Add ESP-SR wake word detection
#include "esp_wn_iface.h"
#include "esp_wn_models.h"

// Initialize wake word detection
// Trigger recording only when wake word detected
```

## NFC Integration (Future)

For NFC functionality with PN532:
1. Connect PN532 to I2C bus (same as audio codec)
2. Use different I2C address (PN532 default: 0x24)
3. Implement NDEF tag reading/writing
4. Coordinate with Flutter app for NFC authentication

## Troubleshooting

### Audio Not Recording
- Check I2S pins are not conflicting
- Verify audio board initialization: `audio_board_init()`
- Monitor logs for codec errors

### WiFi Connection Failed
- Verify SSID and password in menuconfig or NVS
- Check WiFi signal strength
- Ensure WiFi is 2.4GHz (ESP32 doesn't support 5GHz)

### MQTT Not Connecting
- Verify broker URL format: `mqtt://broker.example.com:1883`
- Check firewall/network settings
- Ensure broker allows anonymous connections (or add credentials)

### Lock Not Responding
- If using GPIO: Verify pin isn't used by other peripherals
- If using I2C expander: Check I2C address and wiring
- Test with multimeter: Measure voltage on control pin

## Development Tips

1. **Start Simple**: Test each component individually
   - WiFi connection first
   - Audio recording to SD card
   - HTTP requests
   - MQTT separately
   - Lock control

2. **Use Serial Monitor**: ESP-IDF provides detailed logs
   ```bash
   idf.py monitor
   ```

3. **Adjust Log Levels**: In code or menuconfig
   ```c
   esp_log_level_set("VOICE_LOCK", ESP_LOG_DEBUG);
   ```

4. **Memory Management**: ESP32 has limited RAM
   - Use PSRAM if available (enabled in sdkconfig)
   - Free buffers after use
   - Monitor heap usage: `esp_get_free_heap_size()`

## Next Steps

1. **Configure your backend**: Set up voice verification API
2. **Set up MQTT broker**: Use Mosquitto, HiveMQ, or AWS IoT
3. **Wire lock mechanism**: Connect to GPIO or I2C expander
4. **Test voice recording**: Verify audio quality and duration
5. **Implement wake word**: Add ESP-SR for hands-free operation
6. **Add NFC support**: Integrate PN532 for NFC authentication
7. **Mobile app**: Develop Flutter app for MQTT control

## License

This project is part of the LockWise system.

## Support

For ESP-IDF and ESP-ADF documentation:
- [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/en/latest/)
- [ESP-ADF Programming Guide](https://docs.espressif.com/projects/esp-adf/en/latest/)
- [ESP32-LyraT v4.3 Getting Started](https://docs.espressif.com/projects/esp-adf/en/latest/get-started/get-started-esp32-lyrat.html)
