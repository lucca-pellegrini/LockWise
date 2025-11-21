/* Main Application */

#include "config.h"
#include "driver/i2c.h"
#include "driver/i2c_master.h"
#include "esp_err.h"
#include "freertos/projdefs.h"
#include "hal/i2c_types.h"
#include "board_pins_config.h"
#include "wifi.h"
#include "mqtt.h"
#include "audio_stream.h"
#include "serial.h"
#include "lock.h"
#include "esp_log.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(4, 1, 0))
#include "esp_netif.h"
#else
#include "tcpip_adapter.h"
#endif

static const char *TAG = "LOCKWISE:MAIN";

void app_main(void)
{
	// Initialize lock control GPIO (LED indicator)
	gpio_config_t io_conf = {
		.pin_bit_mask = (1ULL << LOCK_CONTROL_GPIO),
		.mode = GPIO_MODE_OUTPUT,
	};
	gpio_config(&io_conf);
	lock_door();

	esp_log_level_set("*", ESP_LOG_WARN);
	esp_log_level_set(TAG, ESP_LOG_INFO);

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
	i2c_config_t old_cfg;
	get_i2c_pins(I2C_NUM_0, &old_cfg);
	i2c_master_bus_config_t bus_config = {
		.i2c_port = I2C_NUM_0,
		.sda_io_num = old_cfg.sda_io_num,
		.scl_io_num = old_cfg.scl_io_num,
		.clk_source = I2C_CLK_SRC_DEFAULT,
		.glitch_ignore_cnt = 7,
	};
	i2c_master_bus_handle_t bus_handle;
	i2c_new_master_bus(&bus_config, &bus_handle);
	for (uint8_t addr = 1; addr < 127; ++addr) {
		esp_err_t ret = i2c_master_probe(bus_handle, addr, 100);
		if (ret == ESP_OK)
			ESP_LOGI(TAG, "Found device at %02X", addr);
	}
	ESP_LOGI(TAG, "I²C scan complete!");

	// Main loop - can be used for button monitoring or other tasks
	while (1) {
		vTaskDelay(pdMS_TO_TICKS(1000));
	}
}
