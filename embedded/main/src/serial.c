/* Serial Command Implementation */

#include "audio_stream.h"
#include "config.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "freertos/task.h"
#include "lock.h"
#include "mqtt.h"
#include "nvs_flash.h"
#include "serial.h"
#include "system_utils.h"
#include <string.h>

static const char *TAG = "\033[1mLOCKWISE:\033[36mSERIAL\033[0m\033[36m";

/**
 * @brief Executa comando recebido via serial.
 *
 * @param buffer Buffer contendo o comando a executar.
 *
 * Interpreta comandos como update_config, unlock, lock, record, etc.
 */
static void run_command(char buffer[256]);

void serial_command_task(void *pvParameters)
{
	esp_log_level_set(TAG, ESP_LOG_INFO);
	ESP_LOGI(TAG, "Serial command task started");

	char buffer[256];
	int index = 0;

	for (;;) {
		uint8_t data;
		int len = uart_read_bytes(UART_NUM_0, &data, 1, pdMS_TO_TICKS(10));
		if (len > 0) {
			if (data == '\n' || data == '\r') {
				buffer[index] = '\0';
				if (index > 0)
					ESP_LOGI(TAG, "Received command: %s", buffer);
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
		if (sscanf(buffer + 14, "%31s %255[^\n]", key, value) == 2)
			update_config(key, value);
		else
			ESP_LOGW(TAG, "Invalid update_config format");
	} else if (strcasecmp(buffer, "unlock") == 0) {
		unlock_door(DOOR_REASON_SERIAL);
	} else if (strcasecmp(buffer, "lock") == 0) {
		lock_door(DOOR_REASON_SERIAL);
	} else if (strcasecmp(buffer, "record") == 0) {
		audio_stream_send_cmd(AUDIO_STREAM_START);
	} else if (strcasecmp(buffer, "stop") == 0) {
		audio_stream_send_cmd(AUDIO_STREAM_STOP);
	} else if (strcasecmp(buffer, "reboot") == 0) {
		cleanup_restart();
	} else if (strcasecmp(buffer, "lockdown") == 0) {
		cleanup_halt();
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
	} else if (strcasecmp(buffer, "pair") == 0) {
		mqtt_publish_status("ENTERING_PAIRING_MODE");
		update_config("pairing_mode", "1");
		cleanup_restart();
	} else {
		ESP_LOGW(TAG, "Unknown command: %s", buffer);
	}
}
