/* Serial Command Implementation */

#include "serial.h"
#include "config.h"
#include "lock.h"
#include "mqtt.h"
#include "audio_stream.h"
#include "esp_log.h"
#include "driver/uart.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>
#include "esp_system.h"
#include "nvs_flash.h"

static const char *TAG = "LOCKWISE_SERIAL";

static void run_command(char buffer[256]);

void serial_command_task(void *pvParameters)
{
	ESP_LOGI(TAG, "Serial command task started");

	char buffer[256];
	int index = 0;

	while (1) {
		uint8_t data;
		int len = uart_read_bytes(UART_NUM_0, &data, 1, pdMS_TO_TICKS(10));
		if (len > 0) {
			if (data == '\n' || data == '\r') {
				buffer[index] = '\0';
				if (index > 0) {
					ESP_LOGI(TAG, "Received command: %s", buffer);
				}
				index = 0;

				run_command(buffer);
			} else if (index < sizeof(buffer) - 1) {
				buffer[index++] = data;
			}
		}
	}
}

static void run_command(char buffer[256])
{
	if (strncmp(buffer, "update_config ", 14) == 0) {
		char key[32], value[256];
		if (sscanf(buffer + 14, "%31s %255[^\n]", key, value) == 2) {
			update_config(key, value);
		} else {
			ESP_LOGW(TAG, "Invalid update_config format");
		}
	} else if (strcasecmp(buffer, "unlock") == 0) {
		unlock_door();
	} else if (strcasecmp(buffer, "lock") == 0) {
		lock_door();
	} else if (strcasecmp(buffer, "record") == 0) {
		audio_stream_send_cmd(AUDIO_STREAM_START);
	} else if (strcasecmp(buffer, "stop") == 0) {
		audio_stream_send_cmd(AUDIO_STREAM_STOP);
	} else if (strcasecmp(buffer, "reboot") == 0) {
		mqtt_publish_status("RESTARTING");
		esp_restart();
	} else if (strcasecmp(buffer, "flash") == 0) {
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
	} else {
		ESP_LOGW(TAG, "Unknown command: %s", buffer);
	}
}
