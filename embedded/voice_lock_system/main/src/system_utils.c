/* System Utilities Implementation */

#include "system_utils.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lock.h"
#include "mqtt.h"

static const char *TAG = "\033[1mLOCKWISE:\033[91mSYSTEM\033[1m\033[91m";

extern TaskHandle_t heartbeat_task;

static void cleanup(void)
{
	if (heartbeat_task) {
		vTaskDelete(heartbeat_task);
		heartbeat_task = NULL;
	}

	// Disconnect MQTT if connected (send DISCONNECT packet)
	if (mqtt_client) {
		esp_mqtt_client_disconnect(mqtt_client);
		esp_mqtt_client_stop(mqtt_client);
		esp_mqtt_client_destroy(mqtt_client);
		mqtt_client = NULL;
	}

	// Disconnect WiFi
	esp_wifi_disconnect();
	esp_wifi_stop();
}

void cleanup_restart(void)
{
	// Publish restarting status before disconnecting
	mqtt_publish_status("RESTARTING");
	lock_door();

	cleanup();
	ESP_LOGW(TAG, "Restarting system...");
	puts("\033[3m\033[1m\033[96m==============================   Rebooting...   ===============================\033[0m\n");
	vTaskDelay(pdMS_TO_TICKS(100));
	esp_restart();
}

void cleanup_halt()
{
	mqtt_publish_status("LOCKING_DOWN");
	lock_door();

	cleanup();
	ESP_LOGE(TAG, "LOCKING DOWN SYSTEM!");
	puts("\033[3m\033[1m\033[91m\033[7m\033[5m!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!   LOCKING DOWN   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\033[0m\n");
	vTaskDelay(pdMS_TO_TICKS(100));
	esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
	esp_deep_sleep_start();
}
