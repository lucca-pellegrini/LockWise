/* Main Application */

#include "audio_stream.h"
#include "board.h"
#include "config.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/uart.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "freertos/projdefs.h"
#include "freertos/task.h"
#include "hal/i2c_types.h"
#include "i2c_bus.h"
#include "lock.h"
#include "mqtt.h"
#include "nvs_flash.h"
#include "serial.h"
#include "wifi.h"

static const char *TAG = "LOCKWISE:MAIN";

static i2c_master_bus_handle_t g_i2c_handle;
static TaskHandle_t setup_blink_task = NULL;

void app_main(void)
{
	// Set log level
	esp_log_level_set("*", ESP_LOG_WARN);
	esp_log_level_set(TAG, ESP_LOG_INFO);

	uint64_t pin_bit_mask; // GPIO bit mask
	pin_bit_mask = (1ULL << LOCK_INDICATOR_LED_GPIO); // Enable indicator LED

	// If an actual GPIO pin is set as the lock actuator, enable it too
	pin_bit_mask |= (LOCK_ACTUATOR_GPIO >= 0) ? (1ULL << LOCK_ACTUATOR_GPIO) : 0;

	// Apply configuration
	gpio_config(&(gpio_config_t){ .pin_bit_mask = pin_bit_mask, .mode = GPIO_MODE_OUTPUT });

	// Ensure LED is off initially (not streaming)
	gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);

	// Initialize lock mutex and lock door
	lock_init();

	// Start setup blink
	xTaskCreate(blink, "setup_blink", 1024, (void *)200, 1, &setup_blink_task);

	// Configure UART for serial input
	uart_config_t uart_config = {
		.baud_rate = 115200,
		.data_bits = UART_DATA_8_BITS,
		.parity = UART_PARITY_DISABLE,
		.stop_bits = UART_STOP_BITS_1,
		.flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
		.source_clk = UART_SCLK_APB,
	};
	uart_param_config(UART_NUM_0, &uart_config);
	uart_driver_install(UART_NUM_0, 256, 0, 0, NULL, 0);

	ESP_LOGI(TAG, "=== Voice-Controlled Lock System ===");

	// Initialize NVS
	esp_err_t err = nvs_flash_init();
	if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
		ESP_ERROR_CHECK(nvs_flash_erase());
		err = nvs_flash_init();
	}
	ESP_ERROR_CHECK(err);

	// Initialize audio board early to set up I2C
	audio_board_handle_t board_handle = audio_board_init();
	g_i2c_handle = i2c_bus_get_master_handle(I2C_NUM_0);

	// Initialize network interface
#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(4, 1, 0))
	ESP_ERROR_CHECK(esp_netif_init());
#else
	tcpip_adapter_init();
#endif

	// Load configuration
	load_config_from_nvs();

	// Start serial command task early to allow config updates before wifi connects
	xTaskCreate(serial_command_task, "serial_cmd", 4096, NULL, 4, NULL);

	// Initialize WiFi
	wifi_init();

	// Initialize system clock
	esp_sntp_config_t ntp_config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
	ESP_LOGI(TAG, "Initializing system clock via SNTP: %s", *ntp_config.servers);
	esp_netif_sntp_init(&ntp_config);
	if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(15000)) != ESP_OK)
		ESP_LOGE(TAG, "Failed to update system time within 15s timeout");

	// Initialize MQTT
	mqtt_init();

	// Initialize audio stream
	audio_stream_init();

	ESP_LOGI(TAG, "System initialized successfully");
	ESP_LOGI(TAG, "Waiting for voice commands or MQTT messages...");

	// Start MQTT heartbeat task
	if (config.mqtt_heartbeat_enable) {
		xTaskCreate(mqtt_heartbeat_task, "mqtt_heartbeat", 4096, NULL, 3, NULL);
	}

	ESP_LOGI(TAG, "Starting I²C scan…");
	for (uint8_t addr = 1; addr < 127; ++addr) {
		esp_err_t ret = i2c_master_probe(g_i2c_handle, addr, 100);
		if (ret == ESP_OK)
			ESP_LOGI(TAG, "Found device at %02X", addr);
	}
	ESP_LOGI(TAG, "I²C scan complete!");

	// Stop setup blink
	if (setup_blink_task) {
		vTaskDelete(setup_blink_task);
		setup_blink_task = NULL;
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);
	}

	// Main loop - can be used for button monitoring or other tasks
	for (;;) {
		vTaskDelay(pdMS_TO_TICKS(1000));
	}
}
