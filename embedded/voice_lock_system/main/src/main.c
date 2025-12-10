/* Main Application */

#include "audio_stream.h"
#include "board.h"
#include "config.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/uart.h"
#include "esp_err.h"
#include <lwip/sockets.h>
#include <lwip/netdb.h>
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
#include <cJSON.h>
#include <string.h>

static const char *TAG = "LOCKWISE:MAIN";

static i2c_master_bus_handle_t g_i2c_handle;
static TaskHandle_t setup_blink_task = NULL;
static int pairing_sock = -1;

static void start_pairing_server(void);
static void handle_pairing_client(int client_sock);
static void parse_configure_request(const char *request, char *wifi_ssid, char *wifi_pass, char *user_key,
				    char *device_id);

static void start_pairing_server(void)
{
	struct sockaddr_in server_addr;
	pairing_sock = socket(AF_INET, SOCK_STREAM, 0);
	if (pairing_sock < 0) {
		ESP_LOGE(TAG, "Failed to create socket");
		return;
	}

	server_addr.sin_family = AF_INET;
	server_addr.sin_port = htons(80);
	server_addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if (bind(pairing_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
		ESP_LOGE(TAG, "Failed to bind socket");
		close(pairing_sock);
		pairing_sock = -1;
		return;
	}

	if (listen(pairing_sock, 1) < 0) {
		ESP_LOGE(TAG, "Failed to listen on socket");
		close(pairing_sock);
		pairing_sock = -1;
		return;
	}

	ESP_LOGI(TAG, "Pairing server started on port 80");

	// Accept connections in a loop
	while (1) {
		struct sockaddr_in client_addr;
		socklen_t client_addr_len = sizeof(client_addr);
		int client_sock = accept(pairing_sock, (struct sockaddr *)&client_addr, &client_addr_len);
		if (client_sock >= 0) {
			ESP_LOGI(TAG, "Client connected");
			handle_pairing_client(client_sock);
			close(client_sock);
		}
	}
}

static void handle_pairing_client(int client_sock)
{
	char buffer[1024];
	int len = recv(client_sock, buffer, sizeof(buffer) - 1, 0);
	if (len <= 0) {
		return;
	}
	buffer[len] = '\0';

	// Simple HTTP request parsing
	if (strstr(buffer, "POST /configure") && strstr(buffer, "Content-Type: application/json")) {
		char wifi_ssid[32] = "";
		char wifi_pass[64] = "";
		char user_key[256] = "";
		char device_id[64] = "";

		parse_configure_request(buffer, wifi_ssid, wifi_pass, user_key, device_id);

		if (strlen(wifi_ssid) > 0 && strlen(wifi_pass) > 0 && strlen(user_key) > 0) {
			// Store configuration
			update_config("wifi_ssid", wifi_ssid);
			update_config("wifi_pass", wifi_pass);
			update_config("user_pub_key", user_key);
			update_config("device_id", device_id);
			// pairing_mode is already set to 0 at the start of pairing mode

			// Send success response
			const char *response =
				"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nConfiguration received. Rebooting...\n";
			send(client_sock, response, strlen(response), 0);

			ESP_LOGI(TAG, "Configuration stored, rebooting...");
			vTaskDelay(pdMS_TO_TICKS(1000));
			esp_restart();
		} else {
			const char *response =
				"HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid configuration\n";
			send(client_sock, response, strlen(response), 0);
		}
	} else {
		const char *response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot found\n";
		send(client_sock, response, strlen(response), 0);
	}
}

static void parse_configure_request(const char *request, char *wifi_ssid, char *wifi_pass, char *user_key,
				    char *device_id)
{
	// Find JSON body
	const char *json_start = strstr(request, "\r\n\r\n");
	if (!json_start)
		return;
	json_start += 4;

	// Simple JSON parsing (not robust, but works for our case)
	const char *ssid_start = strstr(json_start, "\"wifi_ssid\":\"");
	if (ssid_start) {
		ssid_start += 13;
		const char *ssid_end = strchr(ssid_start, '"');
		if (ssid_end) {
			size_t len = ssid_end - ssid_start;
			if (len < 32) {
				strncpy(wifi_ssid, ssid_start, len);
				wifi_ssid[len] = '\0';
			}
		}
	}

	const char *pass_start = strstr(json_start, "\"wifi_password\":\"");
	if (pass_start) {
		pass_start += 16;
		const char *pass_end = strchr(pass_start, '"');
		if (pass_end) {
			size_t len = pass_end - pass_start;
			if (len < 64) {
				strncpy(wifi_pass, pass_start, len);
				wifi_pass[len] = '\0';
			}
		}
	}

	const char *key_start = strstr(json_start, "\"user_key\":\"");
	if (key_start) {
		key_start += 12;
		const char *key_end = strchr(key_start, '"');
		if (key_end) {
			size_t len = key_end - key_start;
			if (len < 256) {
				strncpy(user_key, key_start, len);
				user_key[len] = '\0';
			}
		}
	}

	const char *id_start = strstr(json_start, "\"device_id\":\"");
	if (id_start) {
		id_start += 13;
		const char *id_end = strchr(id_start, '"');
		if (id_end) {
			size_t len = id_end - id_start;
			if (len < 64) {
				strncpy(device_id, id_start, len);
				device_id[len] = '\0';
			}
		}
	}
}

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

	// Check if in pairing mode
	if (config.pairing_mode) {
		ESP_LOGI(TAG, "Device is in pairing mode, starting AP");
		// Immediately reset pairing mode so we don't get stuck
		update_config("pairing_mode", "0");

		// Start pairing blink (1000ms period, 10ms on)
		static blink_params_t pairing_blink_params = { 1000, 10 };
		xTaskCreate(blink, "pairing_blink", 1024, &pairing_blink_params, 1, NULL);

		// Initialize WiFi in AP mode
		wifi_init_ap();

		// Start pairing server
		start_pairing_server();

		// Should not reach here
		for (;;)
			vTaskDelay(pdMS_TO_TICKS(1000));
	} else {
		// Start setup blink (400ms period, 200ms on)
		static blink_params_t setup_blink_params = { 400, 200 };
		xTaskCreate(blink, "setup_blink", 1024, &setup_blink_params, 1, &setup_blink_task);
	}

	// Start serial command task early to allow config updates before wifi connects
	xTaskCreate(serial_command_task, "serial_cmd", 4096, NULL, 4, NULL);

	// Initialize WiFi (station mode) only if not in pairing mode
	if (!config.pairing_mode) {
		wifi_init();
	}

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
