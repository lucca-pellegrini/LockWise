/* MQTT Management Implementation */

#include "mqtt.h"
#include "config.h"
#include "lock.h"
#include "audio_stream.h"
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>
#include <errno.h>
#include <arpa/inet.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"
#include <cbor.h>

static const char *TAG = "LOCKWISE_MQTT";

/* Global MQTT client handle */
esp_mqtt_client_handle_t mqtt_client;

/* External reference to embedded certificate */
extern const uint8_t mqtt_ca_pem_start[] asm("_binary_mqtt_ca_pem_start");
extern const uint8_t mqtt_ca_pem_end[] asm("_binary_mqtt_ca_pem_end");

/* Forward declarations */
static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data);
static void process_cbor_command(CborValue *value);
static void handle_update_config_command(CborValue *map_value);

static void process_cbor_command(CborValue *value)
{
	CborValue cmd_val;
	if (cbor_value_map_find_value(value, "command", &cmd_val) == CborNoError &&
	    cbor_value_is_text_string(&cmd_val)) {
		char command[32];
		size_t cmd_len = sizeof(command);

		if (cbor_value_copy_text_string(&cmd_val, command, &cmd_len, NULL) == CborNoError) {
			ESP_LOGI(TAG, "Command: %s", command);

			if (!strcasecmp(command, "UNLOCK")) {
				unlock_door();
			} else if (!strcasecmp(command, "LOCK")) {
				lock_door();
			} else if (!strcasecmp(command, "RECORD")) {
				audio_stream_send_cmd(AUDIO_STREAM_START);
			} else if (!strcasecmp(command, "STOP")) {
				audio_stream_send_cmd(AUDIO_STREAM_STOP);
			} else if (!strcasecmp(command, "FLASH")) {
				// TODO: Handle flash erase
			} else if (!strcasecmp(command, "REBOOT")) {
				mqtt_publish_status("RESTARTING");
				esp_restart();
			} else if (!strcasecmp(command, "UPDATE_CONFIG")) {
				handle_update_config_command(value);
			}
		}
	} else {
		ESP_LOGW(TAG, "No 'command' field or not text");
	}
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
		update_config(config_key, config_value);
		mqtt_publish_status("CONFIG_UPDATED");
	} else {
		mqtt_publish_status("INVALID_UPDATE_CONFIG_FORMAT");
		ESP_LOGW(TAG, "Invalid UPDATE_CONFIG CBOR format");
	}
}

static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
	static bool have_already_connected;
	esp_mqtt_event_handle_t event = event_data;

	switch ((esp_mqtt_event_id_t)event_id) {
	case MQTT_EVENT_CONNECTED:
		ESP_LOGI(TAG, "MQTT Connected");
		// Subscribe to device-specific topic
		char topic[96];
		snprintf(topic, sizeof(topic), "lockwise/%s/control", device_id);
		esp_mqtt_client_subscribe(mqtt_client, topic, 0);
		ESP_LOGI(TAG, "Subscribed to topic: %s", topic);

		if (!have_already_connected) {
			have_already_connected = true;
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

void mqtt_init(void)
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

void mqtt_publish_status(const char *status)
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

void mqtt_heartbeat_task(void *pvParameters)
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
