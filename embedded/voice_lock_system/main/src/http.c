/* HTTP Management Implementation */

#include "http.h"
#include "config.h"
#include "audio.h"
#include "lock.h"
#include "esp_log.h"
#include "esp_http_client.h"

static const char *TAG = "LOCKWISE_HTTP";

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

esp_err_t send_audio_to_backend(void)
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