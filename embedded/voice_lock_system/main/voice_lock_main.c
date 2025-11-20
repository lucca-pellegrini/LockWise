/* Voice-Controlled Lock System
 *
 * This application controls a door lock via:
 * 1. Voice authentication (record audio, send to backend for verification)
 * 2. MQTT commands from mobile app
 *
 * Features:
 * - Audio recording from ESP32-LyraT microphones
 * - WiFi connectivity with stored credentials
 * - HTTP client for backend API communication
 * - MQTT client for mobile app control
 * - Automatic lock timeout (20 seconds)
 * - NVS storage for WiFi credentials and device ID
 */

#include "esp_system.h"
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>
#include <errno.h>
#include <arpa/inet.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "freertos/timers.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "nvs_flash.h"
#include "nvs.h"

#include "esp_http_client.h"
#include "mqtt_client.h"
#include <cbor.h>
#include "audio_event_iface.h"
#include "audio_common.h"
#include "audio_pipeline.h"
#include "board.h"
#include "i2s_stream.h"
#include "raw_stream.h"
#include "filter_resample.h"
#include "esp_peripherals.h"
#include "periph_wifi.h"

#include "audio_idf_version.h"

#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(4, 1, 0))
#include "esp_netif.h"
#else
#include "tcpip_adapter.h"
#endif

static const char *TAG = "LOCKWISE";

/* Configuration - Use Kconfig values, can be overridden via NVS */
#define DEFAULT_WIFI_SSID CONFIG_WIFI_SSID
#define DEFAULT_WIFI_PASSWORD CONFIG_WIFI_PASSWORD
#define DEFAULT_DEVICE_ID CONFIG_DEVICE_ID
#define DEFAULT_BACKEND_URL CONFIG_BACKEND_URL
#define DEFAULT_MQTT_BROKER CONFIG_MQTT_BROKER_URL

#define AUDIO_SAMPLE_RATE 16000
#define AUDIO_BITS 16
#define AUDIO_CHANNELS 1
#define RECORD_DURATION_MS 3000 // 3 seconds for voice sample
#define LOCK_TIMEOUT_MS 20000 // 20 seconds auto-lock

/* GPIO for lock control - You'll need to specify actual GPIO pin */
/* Since GPIO pins are limited, you may need to use I2C GPIO expander */
#define LOCK_CONTROL_GPIO -1 // TODO: Define actual GPIO or I2C control

/* Lock states */
typedef enum { LOCK_STATE_LOCKED, LOCK_STATE_UNLOCKED, LOCK_STATE_AUTHENTICATING } lock_state_t;

/* Global handles */
static audio_pipeline_handle_t pipeline;
static audio_element_handle_t i2s_reader, raw_writer;
static esp_mqtt_client_handle_t mqtt_client;
static TimerHandle_t lock_timer;
static lock_state_t current_lock_state = LOCK_STATE_LOCKED;
static bool have_connected = false;

/* Configuration storage */
static char wifi_ssid[32];
static char wifi_password[64];
static char device_id[64];
static char backend_url[256];
static char mqtt_broker_url[256];

/* Audio buffer for recording */
#define AUDIO_BUFFER_SIZE (AUDIO_SAMPLE_RATE * AUDIO_CHANNELS * (AUDIO_BITS / 8) * (RECORD_DURATION_MS / 1000))
static uint8_t *audio_buffer = NULL;
static size_t audio_buffer_len = 0;

/* Function prototypes */
static void load_config_from_nvs(void);
static void wifi_init(void);
static void mqtt_init(void);
static void mqtt_publish_status(const char *status);
static void mqtt_heartbeat_task(void *pvParameters);
static void audio_pipeline_setup(void);
static esp_err_t start_voice_recording(void);
static esp_err_t send_audio_to_backend(void);
static void unlock_door(void);
static void lock_door(void);
static void lock_timeout_callback(TimerHandle_t xTimer);
static void handle_update_config_command(CborValue *map_value);

/* NVS Configuration Management */
static void load_config_from_nvs(void)
{
	nvs_handle_t nvs_handle;
	esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
	int nvs_available = (err == ESP_OK);

	if (!nvs_available) {
		ESP_LOGW(TAG, "NVS unavailable, using all defaults");
	}

	// Load WiFi SSID
	size_t required_size = sizeof(wifi_ssid);
	if (nvs_available && nvs_get_str(nvs_handle, "wifi_ssid", wifi_ssid, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded wifi_ssid from NVS: %s", wifi_ssid);
	} else {
		strcpy(wifi_ssid, DEFAULT_WIFI_SSID);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "wifi_ssid", wifi_ssid);
			ESP_LOGW(TAG, "Using provisioned wifi_ssid and saved to NVS: %s", wifi_ssid);
		}
	}

	// Load WiFi Password
	required_size = sizeof(wifi_password);
	if (nvs_available && nvs_get_str(nvs_handle, "wifi_pass", wifi_password, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded wifi_pass from NVS: [REDACTED]");
	} else {
		strcpy(wifi_password, DEFAULT_WIFI_PASSWORD);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "wifi_pass", wifi_password);
			ESP_LOGW(TAG, "Using provisioned wifi_pass and saved to NVS: [REDACTED]");
		}
	}

	// Load Device ID
	required_size = sizeof(device_id);
	if (nvs_available && nvs_get_str(nvs_handle, "device_id", device_id, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded device_id from NVS: %s", device_id);
	} else {
		strcpy(device_id, DEFAULT_DEVICE_ID);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "device_id", device_id);
			ESP_LOGW(TAG, "Using provisioned device_id and saved to NVS: %s", device_id);
		}
	}

	// Load Backend URL
	required_size = sizeof(backend_url);
	if (nvs_available && nvs_get_str(nvs_handle, "backend_url", backend_url, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded backend_url from NVS: %s", backend_url);
	} else {
		strcpy(backend_url, DEFAULT_BACKEND_URL);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "backend_url", backend_url);
			ESP_LOGW(TAG, "Using provisioned backend_url and saved to NVS: %s", backend_url);
		}
	}

	// Load MQTT Broker URL
	required_size = sizeof(mqtt_broker_url);
	if (nvs_available && nvs_get_str(nvs_handle, "mqtt_broker", mqtt_broker_url, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded mqtt_broker_url from NVS: %s", mqtt_broker_url);
	} else {
		strcpy(mqtt_broker_url, DEFAULT_MQTT_BROKER);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "mqtt_broker", mqtt_broker_url);
			ESP_LOGW(TAG, "Using provisioned mqtt_broker_url and saved to NVS: %s", mqtt_broker_url);
		}
	}

	if (nvs_available) {
		nvs_commit(nvs_handle);
		nvs_close(nvs_handle);
	}

	ESP_LOGI(TAG, "Device ID: %s", device_id);
}

/* WiFi Initialization */
static void wifi_init(void)
{
	ESP_LOGI(TAG, "Initializing WiFi, SSID: %s", wifi_ssid);

	esp_periph_config_t periph_cfg = DEFAULT_ESP_PERIPH_SET_CONFIG();
	esp_periph_set_handle_t set = esp_periph_set_init(&periph_cfg);

	periph_wifi_cfg_t wifi_cfg = {
		.wifi_config.sta.ssid = {},
		.wifi_config.sta.password = {},
	};

	// Copy SSID and password to the config
	strncpy((char *)wifi_cfg.wifi_config.sta.ssid, wifi_ssid, sizeof(wifi_cfg.wifi_config.sta.ssid));
	strncpy((char *)wifi_cfg.wifi_config.sta.password, wifi_password, sizeof(wifi_cfg.wifi_config.sta.password));

	esp_periph_handle_t wifi_handle = periph_wifi_init(&wifi_cfg);
	esp_periph_start(set, wifi_handle);
	periph_wifi_wait_for_connected(wifi_handle, portMAX_DELAY);

	ESP_LOGI(TAG, "WiFi connected successfully");

	// Get and log IP address
	esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
	if (netif) {
		esp_netif_ip_info_t ip_info;
		esp_netif_get_ip_info(netif, &ip_info);
		ESP_LOGI(TAG, "IP Address: " IPSTR, IP2STR(&ip_info.ip));
		ESP_LOGI(TAG, "Gateway: " IPSTR, IP2STR(&ip_info.gw));
		ESP_LOGI(TAG, "Netmask: " IPSTR, IP2STR(&ip_info.netmask));

		// Get DNS server
		esp_netif_dns_info_t dns_info;
		esp_netif_get_dns_info(netif, ESP_NETIF_DNS_MAIN, &dns_info);
		ESP_LOGI(TAG, "DNS Server: " IPSTR, IP2STR(&dns_info.ip.u_addr.ip4));
	}
}

static void process_cbor_command(CborValue *value)
{
	CborValue cmd_val;
	if (cbor_value_map_find_value(value, "command", &cmd_val) == CborNoError &&
	    cbor_value_is_text_string(&cmd_val)) {
		char command[32];
		size_t cmd_len = sizeof(command);

		if (cbor_value_copy_text_string(&cmd_val, command, &cmd_len, NULL) == CborNoError) {
			ESP_LOGI(TAG, "Command: %s", command);

			if (!strcmp(command, "UNLOCK")) {
				unlock_door();
			} else if (!strcmp(command, "LOCK")) {
				lock_door();
			} else if (!strcmp(command, "FLASH")) {
				switch (nvs_flash_erase()) {
				case ESP_OK:
					mqtt_publish_status("NVS_ERASED");
					break;
				case ESP_ERR_NOT_FOUND:
					mqtt_publish_status("NVS_ERASE_FAILED_NO_SUCH");
					break;
				default:
					mqtt_publish_status("NVS_ERASE_FAILED_UNKNOWN_ERROR");
					break;
				}
			} else if (!strcmp(command, "REBOOT")) {
				mqtt_publish_status("RESTARTING");
				esp_restart();
			} else if (!strcmp(command, "UPDATE_CONFIG")) {
				handle_update_config_command(value);
			}
		}
	} else {
		ESP_LOGW(TAG, "No 'command' field or not text");
	}
}

/* MQTT Event Handler */
static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
	esp_mqtt_event_handle_t event = event_data;

	switch ((esp_mqtt_event_id_t)event_id) {
	case MQTT_EVENT_CONNECTED:
		ESP_LOGI(TAG, "MQTT Connected");
		// Subscribe to device-specific topic
		char topic[96];
		snprintf(topic, sizeof(topic), "lockwise/%s/control", device_id);
		esp_mqtt_client_subscribe(mqtt_client, topic, 0);
		ESP_LOGI(TAG, "Subscribed to topic: %s", topic);

		if (!have_connected) {
			have_connected = true;
			mqtt_publish_status("POWER_ON");
		}

		// Publish connected
		mqtt_publish_status("CONNECTED");
		break;

	case MQTT_EVENT_DISCONNECTED:
		ESP_LOGW(TAG, "MQTT Disconnected, attempting to reconnect");
		esp_mqtt_client_reconnect(mqtt_client);
		break;

	case MQTT_EVENT_DATA:
		ESP_LOGI(TAG, "MQTT CBOR Data received: topic=%.*s", event->topic_len, event->topic);
		ESP_LOGD(TAG, "payload len=%d", event->data_len);

		// Decode CBOR data
		CborParser parser;
		CborValue value;
		CborError err = cbor_parser_init((const uint8_t *)event->data, event->data_len, 0, &parser, &value);
		if (err != CborNoError) {
			ESP_LOGW(TAG, "Invalid CBOR data received, error: %d, ignoring", err);
			break;
		}

		ESP_LOGI(TAG, "CBOR parsed successfully");
		if (cbor_value_is_map(&value)) {
			process_cbor_command(&value);
		} else {
			mqtt_publish_status("INVALID_COMMAND");
			ESP_LOGW(TAG, "CBOR is not a map");
		}
		break;

	case MQTT_EVENT_ERROR:
		ESP_LOGE(TAG, "MQTT Error event");
		if (event->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT) {
			ESP_LOGE(TAG, "Last error code reported from esp-tls: 0x%x",
				 event->error_handle->esp_tls_last_esp_err);
			ESP_LOGE(TAG, "Last tls stack error number: 0x%x", event->error_handle->esp_tls_stack_err);
			ESP_LOGE(TAG, "Last captured errno : %d (%s)", event->error_handle->esp_transport_sock_errno,
				 strerror(event->error_handle->esp_transport_sock_errno));
		} else if (event->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED) {
			ESP_LOGE(TAG, "Connection refused error: 0x%x", event->error_handle->connect_return_code);
		}
		break;

	default:
		break;
	}
}

/* MQTT Initialization */

// External references to embedded certificate (if TLS is used)
extern const uint8_t mqtt_ca_pem_start[] asm("_binary_mqtt_ca_pem_start");
extern const uint8_t mqtt_ca_pem_end[] asm("_binary_mqtt_ca_pem_end");

static void mqtt_init(void)
{
	ESP_LOGI(TAG, "Initializing MQTT, broker: %s", mqtt_broker_url);

	// Extract hostname from URL for DNS testing
	char hostname[128] = { 0 };
	char *host_start = strstr(mqtt_broker_url, "://");
	if (host_start) {
		host_start += 3; // Skip "://"
		char *port_start = strchr(host_start, ':');
		char *path_start = strchr(host_start, '/');
		int len = 0;

		if (port_start) {
			len = port_start - host_start;
		} else if (path_start) {
			len = path_start - host_start;
		} else {
			len = strlen(host_start);
		}

		if (len > 0 && len < sizeof(hostname)) {
			strncpy(hostname, host_start, len);
			hostname[len] = '\0';

			// Test DNS resolution
			ESP_LOGI(TAG, "Testing DNS resolution for: %s", hostname);
			struct addrinfo hints = {
				.ai_family = AF_UNSPEC,
				.ai_socktype = SOCK_STREAM,
			};
			struct addrinfo *res;
			int err = getaddrinfo(hostname, NULL, &hints, &res);
			if (err != 0 || res == NULL) {
				ESP_LOGE(TAG, "DNS lookup failed for %s: %d", hostname, err);
			} else {
				// Print resolved IP addresses
				for (struct addrinfo *p = res; p != NULL; p = p->ai_next) {
					if (p->ai_family == AF_INET) {
						struct sockaddr_in *ipv4 = (struct sockaddr_in *)p->ai_addr;
						ESP_LOGI(TAG, "DNS resolved to: %s", inet_ntoa(ipv4->sin_addr));
					}
				}
				freeaddrinfo(res);
			}

			// Test TCP connection to MQTT broker
			ESP_LOGI(TAG, "Testing TCP connection to %s:8883", hostname);
			int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
			if (sock >= 0) {
				struct sockaddr_in dest_addr;
				dest_addr.sin_family = AF_INET;
				dest_addr.sin_port = htons(8883);

				// Resolve hostname again for connection test
				struct addrinfo *res2;
				err = getaddrinfo(hostname, "8883", &hints, &res2);
				if (err == 0 && res2) {
					struct sockaddr_in *ipv4 = (struct sockaddr_in *)res2->ai_addr;
					memcpy(&dest_addr.sin_addr, &ipv4->sin_addr, sizeof(dest_addr.sin_addr));

					// Set socket timeout
					struct timeval timeout = { .tv_sec = 5, .tv_usec = 0 };
					setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
					setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

					int connect_result =
						connect(sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr));
					if (connect_result == 0) {
						ESP_LOGI(TAG, "TCP connection successful!");
						close(sock);
					} else {
						ESP_LOGE(TAG, "TCP connection failed: errno=%d (%s)", errno,
							 strerror(errno));
						close(sock);
					}
					freeaddrinfo(res2);
				} else {
					ESP_LOGE(TAG, "DNS lookup failed for connection test: %d", err);
					close(sock);
				}
			} else {
				ESP_LOGE(TAG, "Failed to create socket: errno=%d", errno);
			}
		}
	}

	esp_mqtt_client_config_t mqtt_cfg = {
		.broker.address.uri = mqtt_broker_url,
		.credentials.client_id = device_id,
		.network.timeout_ms = 30000, // Increase timeout to 30 seconds
		.network.reconnect_timeout_ms = 5000,
		.session.keepalive = 60,
	};

	// If using mqtts://, configure TLS with embedded certificate
	if (strncmp(mqtt_broker_url, "mqtts://", 8) == 0) {
		mqtt_cfg.broker.verification.certificate = (const char *)mqtt_ca_pem_start;
		mqtt_cfg.broker.verification.certificate_len = mqtt_ca_pem_end - mqtt_ca_pem_start;
		ESP_LOGI(TAG, "MQTT TLS enabled with embedded CA certificate (%d bytes)",
			 (int)(mqtt_ca_pem_end - mqtt_ca_pem_start));
	}

	mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
	esp_mqtt_client_register_event(mqtt_client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL);
	esp_mqtt_client_start(mqtt_client);
}

/* MQTT Status Publishing */
static void mqtt_publish_status(const char *status)
{
	if (mqtt_client == NULL) {
		ESP_LOGW(TAG, "MQTT client not initialized, cannot publish status");
		return;
	}

	char topic[96];
	snprintf(topic, sizeof(topic), "lockwise/%s/status", device_id);

	uint8_t cbor_buffer[256];
	CborEncoder encoder, map_encoder;
	cbor_encoder_init(&encoder, cbor_buffer, sizeof(cbor_buffer), 0);
	cbor_encoder_create_map(&encoder, &map_encoder, 2);
	cbor_encode_text_stringz(&map_encoder, "status");
	cbor_encode_text_stringz(&map_encoder, status);
	cbor_encode_text_stringz(&map_encoder, "uptime_ms");
	cbor_encode_uint(&map_encoder, (uint64_t)xTaskGetTickCount() * portTICK_PERIOD_MS);
	cbor_encoder_close_container(&encoder, &map_encoder);
	size_t cbor_len = cbor_encoder_get_buffer_size(&encoder, cbor_buffer);

	int msg_id = esp_mqtt_client_publish(mqtt_client, topic, (const char *)cbor_buffer, cbor_len, 1, 0);
	if (msg_id >= 0) {
		ESP_LOGI(TAG, "Published CBOR status to %s: %s (msg_id=%d)", topic, status, msg_id);
	} else {
		ESP_LOGE(TAG, "Failed to publish status");
	}
}

/* MQTT Heartbeat Task */
static void mqtt_heartbeat_task(void *pvParameters)
{
#ifdef CONFIG_MQTT_HEARTBEAT_ENABLE
	const int interval_ms = CONFIG_MQTT_HEARTBEAT_INTERVAL_SEC * 1000;
	ESP_LOGI(TAG, "Heartbeat task started (interval: %d seconds)", CONFIG_MQTT_HEARTBEAT_INTERVAL_SEC);

	while (1) {
		vTaskDelay(pdMS_TO_TICKS(interval_ms));
		mqtt_publish_status("HEARTBEAT");
	}
#else
	ESP_LOGI(TAG, "Heartbeat disabled in configuration");
	vTaskDelete(NULL);
#endif
}

/* Audio Pipeline Initialization */
static void audio_pipeline_setup(void)
{
	ESP_LOGI(TAG, "Initializing audio pipeline");

	// Initialize audio board
	audio_board_handle_t board_handle = audio_board_init();
	audio_hal_ctrl_codec(board_handle->audio_hal, AUDIO_HAL_CODEC_MODE_ENCODE, AUDIO_HAL_CTRL_START);

	// Create pipeline
	audio_pipeline_cfg_t pipeline_cfg = DEFAULT_AUDIO_PIPELINE_CONFIG();
	pipeline = audio_pipeline_init(&pipeline_cfg);

	// Create I2S stream reader (from microphones)
	i2s_stream_cfg_t i2s_cfg = I2S_STREAM_CFG_DEFAULT();
	i2s_cfg.type = AUDIO_STREAM_READER;

#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0))
	i2s_cfg.chan_cfg.id = CODEC_ADC_I2S_PORT;
	i2s_cfg.std_cfg.slot_cfg.slot_mode = I2S_SLOT_MODE_MONO;
	i2s_cfg.std_cfg.slot_cfg.slot_mask = I2S_STD_SLOT_LEFT;
	i2s_cfg.std_cfg.clk_cfg.sample_rate_hz = AUDIO_SAMPLE_RATE;
#else
	i2s_cfg.i2s_port = CODEC_ADC_I2S_PORT;
	i2s_cfg.i2s_config.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
	i2s_cfg.i2s_config.sample_rate = AUDIO_SAMPLE_RATE;
#endif

	i2s_reader = i2s_stream_init(&i2s_cfg);

	// Create raw stream writer (to buffer)
	raw_stream_cfg_t raw_cfg = RAW_STREAM_CFG_DEFAULT();
	raw_cfg.type = AUDIO_STREAM_WRITER;
	raw_writer = raw_stream_init(&raw_cfg);

	// Register elements to pipeline
	audio_pipeline_register(pipeline, i2s_reader, "i2s");
	audio_pipeline_register(pipeline, raw_writer, "raw");

	// Link elements
	const char *link_tag[2] = { "i2s", "raw" };
	audio_pipeline_link(pipeline, &link_tag[0], 2);

	ESP_LOGI(TAG, "Audio pipeline initialized");
}

/* Start Voice Recording */
static esp_err_t start_voice_recording(void)
{
	ESP_LOGI(TAG, "Starting voice recording for %d ms", RECORD_DURATION_MS);

	current_lock_state = LOCK_STATE_AUTHENTICATING;

	// Allocate buffer if not already done
	if (audio_buffer == NULL) {
		audio_buffer = malloc(AUDIO_BUFFER_SIZE);
		if (audio_buffer == NULL) {
			ESP_LOGE(TAG, "Failed to allocate audio buffer");
			return ESP_FAIL;
		}
	}

	audio_buffer_len = 0;

	// Reset pipeline
	audio_pipeline_reset_ringbuffer(pipeline);
	audio_pipeline_reset_elements(pipeline);

	// Start recording
	audio_pipeline_run(pipeline);

	// Read data from raw stream into buffer
	int bytes_read = 0;
	int timeout_counter = 0;

	while (audio_buffer_len < AUDIO_BUFFER_SIZE && timeout_counter < 100) {
		bytes_read = raw_stream_read(raw_writer, (char *)(audio_buffer + audio_buffer_len),
					     AUDIO_BUFFER_SIZE - audio_buffer_len);

		if (bytes_read > 0) {
			audio_buffer_len += bytes_read;
			timeout_counter = 0;
		} else {
			vTaskDelay(pdMS_TO_TICKS(10));
			timeout_counter++;
		}
	}

	// Stop recording
	audio_pipeline_stop(pipeline);
	audio_pipeline_wait_for_stop(pipeline);
	audio_pipeline_terminate(pipeline);

	ESP_LOGI(TAG, "Recording complete, captured %zu bytes", audio_buffer_len);

	return ESP_OK;
}

/* HTTP Event Handler */
static esp_err_t http_event_handler(esp_http_client_event_t *evt)
{
	static int output_len;

	switch (evt->event_id) {
	case HTTP_EVENT_ON_DATA:
		if (!esp_http_client_is_chunked_response(evt->client)) {
			if (evt->user_data) {
				memcpy(evt->user_data + output_len, evt->data, evt->data_len);
				output_len += evt->data_len;
			}
		}
		break;
	case HTTP_EVENT_ON_FINISH:
		output_len = 0;
		break;
	default:
		break;
	}
	return ESP_OK;
}

/* Send Audio to Backend for Verification */
static esp_err_t send_audio_to_backend(void)
{
	ESP_LOGI(TAG, "Sending audio to backend for verification");

	if (audio_buffer == NULL || audio_buffer_len == 0) {
		ESP_LOGE(TAG, "No audio data to send");
		return ESP_FAIL;
	}

	char response_buffer[512] = { 0 };

	esp_http_client_config_t config = {
		.url = backend_url,
		.method = HTTP_METHOD_POST,
		.event_handler = http_event_handler,
		.user_data = response_buffer,
		.timeout_ms = 5000,
	};

	esp_http_client_handle_t client = esp_http_client_init(&config);

	// Set headers
	esp_http_client_set_header(client, "Content-Type", "application/octet-stream");
	esp_http_client_set_header(client, "X-Device-ID", device_id);

	// Send audio data
	esp_http_client_set_post_field(client, (const char *)audio_buffer, audio_buffer_len);

	esp_err_t err = esp_http_client_perform(client);

	if (err == ESP_OK) {
		int status_code = esp_http_client_get_status_code(client);
		ESP_LOGI(TAG, "HTTP Status = %d, Response = %s", status_code, response_buffer);

		// Check if backend verified the voice
		// Assuming backend returns JSON like: {"verified": true/false}
		if (status_code == 200 && strstr(response_buffer, "\"verified\":true") != NULL) {
			ESP_LOGI(TAG, "Voice verified successfully!");
			esp_http_client_cleanup(client);
			unlock_door();
			return ESP_OK;
		} else {
			ESP_LOGW(TAG, "Voice verification failed");
		}
	} else {
		ESP_LOGE(TAG, "HTTP request failed: %s", esp_err_to_name(err));
	}

	esp_http_client_cleanup(client);
	current_lock_state = LOCK_STATE_LOCKED;
	return ESP_FAIL;
}

/* Lock Timer Callback */
static void lock_timeout_callback(TimerHandle_t xTimer)
{
	ESP_LOGI(TAG, "Lock timeout reached, auto-locking door");
	lock_door();
}

/* Unlock Door */
static void unlock_door(void)
{
	if (current_lock_state == LOCK_STATE_UNLOCKED) {
		ESP_LOGI(TAG, "Door already unlocked");
		return;
	}

	ESP_LOGW(TAG, "Unlocking door");
	current_lock_state = LOCK_STATE_UNLOCKED;

	// TODO: Implement actual GPIO control or I2C command to unlock
	// If using GPIO:
	// gpio_set_level(LOCK_CONTROL_GPIO, 1);

	// If using I2C GPIO expander, implement I2C write here

	// Start auto-lock timer
	if (lock_timer == NULL) {
		lock_timer =
			xTimerCreate("LockTimer", pdMS_TO_TICKS(LOCK_TIMEOUT_MS), pdFALSE, NULL, lock_timeout_callback);
	}
	xTimerStart(lock_timer, 0);

	// Publish status to MQTT
	mqtt_publish_status("UNLOCKED");
}

/* Lock Door */
static void lock_door(void)
{
	if (current_lock_state == LOCK_STATE_LOCKED) {
		ESP_LOGI(TAG, "Door already locked");
		return;
	}

	ESP_LOGI(TAG, "Locking door");
	current_lock_state = LOCK_STATE_LOCKED;

	// TODO: Implement actual GPIO control or I2C command to lock
	// If using GPIO:
	// gpio_set_level(LOCK_CONTROL_GPIO, 0);

	// Stop auto-lock timer
	if (lock_timer != NULL) {
		xTimerStop(lock_timer, 0);
	}

	// Publish status to MQTT
	mqtt_publish_status("LOCKED");
}

static void handle_update_config_command(CborValue *map_value)
{
	CborValue key_val, value_val;
	char config_key[32];
	char config_value[256];
	size_t key_len = sizeof(config_key);
	size_t value_len = sizeof(config_value);

	if (cbor_value_map_find_value(map_value, "key", &key_val) == CborNoError &&
	    cbor_value_map_find_value(map_value, "value", &value_val) == CborNoError &&
	    cbor_value_is_text_string(&key_val) && cbor_value_is_text_string(&value_val) &&
	    cbor_value_copy_text_string(&key_val, config_key, &key_len, NULL) == CborNoError &&
	    cbor_value_copy_text_string(&value_val, config_value, &value_len, NULL) == CborNoError) {
		// Validate key (allow wifi_ssid, wifi_pass, backend_url, mqtt_broker)
		if (!strcmp(config_key, "wifi_ssid") || !strcmp(config_key, "wifi_pass") ||
		    !strcmp(config_key, "backend_url") || !strcmp(config_key, "mqtt_broker")) {
			nvs_handle_t nvs_handle;
			esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
			if (err == ESP_OK) {
				nvs_set_str(nvs_handle, config_key, config_value);
				nvs_commit(nvs_handle);
				nvs_close(nvs_handle);
				mqtt_publish_status("CONFIG_UPDATED");
				ESP_LOGI(TAG, "Updated config %s in NVS", config_key);
			} else {
				mqtt_publish_status("CONFIG_UPDATE_FAILED");
				ESP_LOGE(TAG, "Failed to open NVS for config update: %s", esp_err_to_name(err));
			}
		} else {
			mqtt_publish_status("INVALID_CONFIG_KEY");
			ESP_LOGW(TAG, "Invalid config key: %s", config_key);
		}
	} else {
		mqtt_publish_status("INVALID_UPDATE_CONFIG_FORMAT");
		ESP_LOGW(TAG, "Invalid UPDATE_CONFIG CBOR format");
	}
}

/* Voice Recognition Task */
static void voice_recognition_task(void *pvParameters)
{
	ESP_LOGI(TAG, "Voice recognition task started");

	while (1) {
		// Wait for trigger (in real implementation, use wake word detection or button)
		// For now, we'll use a simple time-based approach
		vTaskDelay(pdMS_TO_TICKS(5000)); // Check every 5 seconds

		// TODO: Implement wake word detection using ESP-SR library
		// For now, we'll trigger recording periodically for testing

		ESP_LOGI(TAG, "Triggering voice authentication (TODO: replace with wake word)");

		if (start_voice_recording() == ESP_OK) {
			send_audio_to_backend();
		}
	}
}

/* Main Application */
void app_main(void)
{
	esp_log_level_set("*", ESP_LOG_INFO);
	esp_log_level_set(TAG, ESP_LOG_INFO);

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

	// Initialize WiFi
	wifi_init();

	// Initialize MQTT
	mqtt_init();

	// Initialize audio pipeline
	audio_pipeline_setup();

	// TODO: Initialize lock control GPIO or I2C
	// If using GPIO:
	// gpio_config_t io_conf = {
	//     .pin_bit_mask = (1ULL << LOCK_CONTROL_GPIO),
	//     .mode = GPIO_MODE_OUTPUT,
	// };
	// gpio_config(&io_conf);

	ESP_LOGI(TAG, "System initialized successfully");
	ESP_LOGI(TAG, "Waiting for voice commands or MQTT messages...");

	// Start voice recognition task
	// xTaskCreate(voice_recognition_task, "voice_rec", 4096, NULL, 5, NULL);

	// Start MQTT heartbeat task
#ifdef CONFIG_MQTT_HEARTBEAT_ENABLE
	xTaskCreate(mqtt_heartbeat_task, "mqtt_heartbeat", 4096, NULL, 3, NULL);
#endif

	// Main loop - can be used for button monitoring or other tasks
	while (1) {
		vTaskDelay(pdMS_TO_TICKS(1000));
	}
}
