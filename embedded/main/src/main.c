/* Main Application */

#include "audio_hal.h"
#include "audio_mem.h"
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
#include "esp_sleep.h"
#include "freertos/projdefs.h"
#include "freertos/task.h"
#include "hal/i2c_types.h"
#include "hal/touch_sensor_types.h"
#include "i2c_bus.h"
#include "lock.h"
#include "mqtt.h"
#include "nvs_flash.h"
#include "serial.h"
#include "system_utils.h"
#include "wifi.h"
#include <cJSON.h>
#include <limits.h>
#include <lwip/netdb.h>
#include <lwip/sockets.h>
#include <string.h>

static const char *TAG = "\033[1mLOCKWISE:\033[0m\033[1mMAIN";

/** @brief Handle global do barramento I2C mestre */
static i2c_master_bus_handle_t g_i2c_handle;
/** @brief Handle da tarefa de piscar durante setup */
static TaskHandle_t setup_blink_task = NULL;
/** @brief Handle da tarefa de piscar idle (acessível de audio_stream.c) */
TaskHandle_t idle_blink_task = NULL;
/** @brief Handle da tarefa de heartbeat MQTT */
TaskHandle_t heartbeat_task = NULL;

/** @brief Handle global da placa de áudio ESP-ADF */
audio_board_handle_t g_board_handle;

/**
 * @brief Tarefa para monitoramento dos sensores de toque.
 *
 * @param param Parâmetros da tarefa (não usado).
 *
 * Monitora continuamente os sensores TOUCH_PAD_NUM8 e TOUCH_PAD_NUM9 para controle manual
 * e modo de pareamento.
 */
static void touch_monitor_task(void *param)
{
	for (;;) {
		uint16_t touch_value;

		touch_pad_read_filtered(TOUCH_PAD_NUM9, &touch_value);
		if (touch_value && touch_value < 750) { // Adjust threshold as needed
			ESP_LOGI(TAG, "Set touch detected, toggling pairing mode");
			update_config("pairing_mode", config.pairing_mode ? "0" : "1");
			while (touch_value < 750)
				touch_pad_read_filtered(TOUCH_PAD_NUM9, &touch_value);
			cleanup_restart();
		}

		touch_pad_read_filtered(TOUCH_PAD_NUM8, &touch_value);
		if (touch_value && touch_value < 750) {
			ESP_LOGI(TAG, "Play touch detected, toggling door");
			unlock_door(DOOR_REASON_BUTTON);
			vTaskDelay(pdMS_TO_TICKS(50));
			while (touch_value < 750)
				touch_pad_read_filtered(TOUCH_PAD_NUM8, &touch_value);
			lock_door(DOOR_REASON_BUTTON);
		}

		vTaskDelay(pdMS_TO_TICKS(50));
	}
}

/**
 * @brief Função principal de entrada da aplicação ESP-IDF.
 *
 * Inicializa todos os componentes do sistema: GPIO, UART, NVS, Wi-Fi, MQTT, áudio,
 * sensores de toque e tarefas de monitoramento. Entra em loop infinito após inicialização.
 */
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
	ESP_LOGI(TAG, "Setting up GPIO");
	gpio_config(&(gpio_config_t){ .pin_bit_mask = pin_bit_mask, .mode = GPIO_MODE_OUTPUT });

	// Ensure LED is off initially (not streaming)
	gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);

	// Initialize lock mutex and lock door
	lock_init();

	// Start setup blink
	xTaskCreate(blink, "setup_blink", 1024, &(blink_params_t){ 400, 200 }, 1, &setup_blink_task);

	// Configure UART for serial input
	const uart_config_t uart_config = {
		.baud_rate = 115200,
		.data_bits = UART_DATA_8_BITS,
		.parity = UART_PARITY_DISABLE,
		.stop_bits = UART_STOP_BITS_1,
		.flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
		.source_clk = UART_SCLK_APB,
	};
	ESP_LOGI(TAG, "Setting up UART driver");
	uart_param_config(UART_NUM_0, &uart_config);
	uart_driver_install(UART_NUM_0, 256, 0, 0, NULL, 0);

	puts("\n\n\033[3m\033[1m\033[96m=================   LockWise: Voice-Controlled Lock System   ==================\033[0m");

	// Initialize NVS
	esp_err_t err = nvs_flash_init();
	if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
		ESP_LOGE(TAG, "Non-volatile memory full. Flashing.");
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

	// Initialize touch pad for Set (TOUCH_PAD_NUM9, IO32) and Play (TOUCH_PAD_NUM8, IO33)
	ESP_LOGI(TAG, "Setting up touch pads");
	touch_pad_init();
	touch_pad_set_voltage(TOUCH_HVOLT_2V7, TOUCH_LVOLT_0V5, TOUCH_HVOLT_ATTEN_1V);
	touch_pad_config(TOUCH_PAD_NUM9, 0);
	touch_pad_config(TOUCH_PAD_NUM8, 0);
	touch_pad_filter_start(10);
	xTaskCreate(touch_monitor_task, "touch_monitor", 4096, NULL, 4, NULL);

	// Check if in pairing mode
	if (config.pairing_mode) {
		ESP_LOGI(TAG, "Device is in pairing mode, starting AP");

		// Immediately reset pairing mode so we don't get stuck
		update_config("pairing_mode", "0");
		puts("\n\033[3m\033[1m\033[91m---------------------------- Entering Pairing Mode ----------------------------\033[0m");

		// Start pairing blink
		vTaskDelete(setup_blink_task);
		xTaskCreate(blink, "pairing_blink", 1024, &(blink_params_t){ 1000, 10 }, 1, NULL);

		// Start pairing server
		start_pairing_server();

		// Should not reach here
		ESP_LOGE(TAG, "Servidor de pareamento terminou!");
		esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
		esp_deep_sleep_start();
	}

	// Initialize WiFi (station mode)
	wifi_init();

	// Initialize audio board after WiFi to avoid ISR conflicts
	ESP_LOGI(TAG, "Setting up audio board");
	g_board_handle = audio_calloc(1, sizeof(struct audio_board_handle));
	AUDIO_MEM_CHECK(TAG, g_board_handle, return);
	audio_hal_codec_config_t cfg = AUDIO_CODEC_DEFAULT_CONFIG();
	cfg.adc_input = AUDIO_HAL_ADC_INPUT_LINE1; // Should be LINE2 for AUX_IN
	g_board_handle->audio_hal = audio_hal_init(&cfg, &AUDIO_CODEC_ES8388_DEFAULT_HANDLE);
	AUDIO_NULL_CHECK(TAG, g_board_handle->audio_hal, return);

	// Get I²C handle
	g_i2c_handle = i2c_bus_get_master_handle(I2C_NUM_0);

	// Initialize system clock
	esp_sntp_config_t ntp_config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
	ESP_LOGI(TAG, "Initializing system clock via SNTP: %s", *ntp_config.servers);
	esp_netif_sntp_init(&ntp_config);

	// Change blink for SNTP sync wait
	vTaskDelete(setup_blink_task);
	xTaskCreate(blink, "setup_blink", 1024, &(blink_params_t){ 200, 100 }, 1, &setup_blink_task);

	if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(15000)) != ESP_OK)
		ESP_LOGE(TAG, "Failed to update system time within 15s timeout");

	// Stop setup blink
	if (setup_blink_task) {
		vTaskDelete(setup_blink_task);
		setup_blink_task = NULL;
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);
	}
	gpio_set_level(LOCK_INDICATOR_LED_GPIO, 1); // Indicate that MQTT is starting

	// Initialize MQTT
	mqtt_init();

	// Initialize audio stream only if voice detection is enabled
	if (config.voice_detection_enable)
		audio_stream_init();

	// Start MQTT heartbeat task
	if (config.mqtt_heartbeat_enable)
		xTaskCreate(mqtt_heartbeat_task, "mqtt_heartbeat", 4096, NULL, 3, &heartbeat_task);

	ESP_LOGD(TAG, "Starting I²C scan…");
	for (uint8_t addr = 1; addr < 127; ++addr)
		if (i2c_master_probe(g_i2c_handle, addr, 100) == ESP_OK)
			ESP_LOGD(TAG, "Found device at %02X", addr);
	ESP_LOGD(TAG, "I²C scan complete!");

	puts("\033[3m\033[1m\033[96m--------------------------- Initialization Complete ---------------------------\033[0m\n");

	// Main loop
	for (;;)
		vTaskDelay(pdMS_TO_TICKS(1000));
}
