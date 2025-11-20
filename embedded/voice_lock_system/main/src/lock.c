/* Lock Control Implementation */

#include "lock.h"
#include "mqtt.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/timers.h"

static const char *TAG = "LOCKWISE_LOCK";

/* Configuration */
#define LOCK_TIMEOUT_MS 20000 // 20 seconds auto-lock

/* Global lock state */
lock_state_t current_lock_state = LOCK_STATE_LOCKED;

/* Lock timer */
static TimerHandle_t lock_timer;

/* Lock Timer Callback */
static void lock_timeout_callback(TimerHandle_t xTimer)
{
	ESP_LOGI(TAG, "Lock timeout reached, auto-locking door");
	lock_door();
}

void unlock_door(void)
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

void lock_door(void)
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