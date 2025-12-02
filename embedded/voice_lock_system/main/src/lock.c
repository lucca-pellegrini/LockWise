/* Lock Control Implementation */

#include "lock.h"
#include "mqtt.h"
#include "config.h"
#include "esp_log.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/timers.h"
#include "freertos/semphr.h"

static const char *TAG = "LOCKWISE:LOCK";

/* Global lock state */
lock_state_t current_lock_state = LOCK_STATE_UNLOCKED;

/* Mutex for lock state */
static SemaphoreHandle_t lock_state_mutex;

/* Lock timer */
static TimerHandle_t lock_timer;

void lock_init(void)
{
	if (lock_state_mutex == NULL)
		lock_state_mutex = xSemaphoreCreateMutex();
}

/* Lock Timer Callback */
static void lock_timeout_callback(TimerHandle_t xTimer)
{
	ESP_LOGI(TAG, "Lock timeout reached, auto-locking door");
	lock_door();
}

void unlock_door(void)
{
	esp_log_level_set(TAG, ESP_LOG_INFO);

	xSemaphoreTake(lock_state_mutex, portMAX_DELAY);

	if (current_lock_state == LOCK_STATE_UNLOCKED) {
		xSemaphoreGive(lock_state_mutex);
		ESP_LOGI(TAG, "Door already unlocked");
		return;
	}

	ESP_LOGW(TAG, "Unlocking door");
	current_lock_state = LOCK_STATE_UNLOCKED;

	// Turn on LED to indicate door is open
	gpio_set_level(LOCK_CONTROL_GPIO, 0);

	// Start auto-lock timer
	if (lock_timer == NULL) {
		lock_timer = xTimerCreate("LockTimer", pdMS_TO_TICKS(config.lock_timeout_ms), pdFALSE, NULL,
					  lock_timeout_callback);
	}
	xTimerStart(lock_timer, 0);

	// Publish status to MQTT
	mqtt_publish_status("UNLOCKED");

	xSemaphoreGive(lock_state_mutex);
}

void lock_door(void)
{
	esp_log_level_set(TAG, ESP_LOG_INFO);

	xSemaphoreTake(lock_state_mutex, portMAX_DELAY);

	if (current_lock_state == LOCK_STATE_LOCKED) {
		xSemaphoreGive(lock_state_mutex);
		ESP_LOGI(TAG, "Door already locked");
		return;
	}

	ESP_LOGI(TAG, "Locking door");
	current_lock_state = LOCK_STATE_LOCKED;

	xSemaphoreGive(lock_state_mutex);

	// Turn off LED to indicate door is closed
	gpio_set_level(LOCK_CONTROL_GPIO, 1);

	// Stop auto-lock timer
	if (lock_timer != NULL) {
		xTimerStop(lock_timer, 0);
	}

	// Publish status to MQTT
	mqtt_publish_status("LOCKED");
}
