/* Lock Control Implementation */

#include "config.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/timers.h"
#include "lock.h"
#include "mqtt.h"

static const char *TAG = "LOCKWISE:LOCK";

/* Lock context singleton */
typedef struct {
	lock_state_t state;
	SemaphoreHandle_t mutex;
	TimerHandle_t timer;
} lock_context_t;

static lock_context_t lock_ctx;

void lock_init(void)
{
	gpio_set_level(LOCK_ACTUATOR_GPIO, 1);
	esp_log_level_set(TAG, ESP_LOG_INFO);

	lock_ctx = (lock_context_t){
		.state = LOCK_STATE_LOCKED,
		.mutex = xSemaphoreCreateMutex(),
		.timer = NULL,
	};
}

/* Lock Timer Callback */
static void lock_timeout_callback(TimerHandle_t xTimer)
{
	ESP_LOGI(TAG, "Lock timeout reached, auto-locking door");
	lock_door();
}

/* Blink Task */
void blink(void *param)
{
	int delay_ms = (int)param;
	for (;;) {
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 1);
		vTaskDelay(pdMS_TO_TICKS(delay_ms));
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);
		vTaskDelay(pdMS_TO_TICKS(delay_ms));
	}
}

void unlock_door(void)
{
	xSemaphoreTake(lock_ctx.mutex, portMAX_DELAY);

	if (lock_ctx.state != LOCK_STATE_UNLOCKED) {
		ESP_LOGW(TAG, "Unlocking door");
		lock_ctx.state = LOCK_STATE_UNLOCKED;

		// Unlock the lock actuator
		gpio_set_level(LOCK_ACTUATOR_GPIO, 0);

		// Publish status to MQTT
		mqtt_publish_status("UNLOCKED");
	} else {
		ESP_LOGI(TAG, "Door already unlocked, restarting auto-lock timer");
	}

	// Start or restart auto-lock timer
	if (!lock_ctx.timer) {
		lock_ctx.timer = xTimerCreate("LockTimer", pdMS_TO_TICKS(config.lock_timeout_ms), pdFALSE, NULL,
					      lock_timeout_callback);
	} else {
		xTimerStop(lock_ctx.timer, 0);
		xTimerStart(lock_ctx.timer, 0);
	}

	xSemaphoreGive(lock_ctx.mutex);
}

void lock_door(void)
{
	xSemaphoreTake(lock_ctx.mutex, portMAX_DELAY);

	if (lock_ctx.state == LOCK_STATE_LOCKED) {
		// Stop auto-lock timer
		if (lock_ctx.timer)
			xTimerStop(lock_ctx.timer, 0);
		xSemaphoreGive(lock_ctx.mutex);
		ESP_LOGI(TAG, "Door already locked");
		return;
	}

	ESP_LOGI(TAG, "Locking door");
	lock_ctx.state = LOCK_STATE_LOCKED;

	xSemaphoreGive(lock_ctx.mutex);

	// Lock the lock actuator
	gpio_set_level(LOCK_ACTUATOR_GPIO, 1);

	// Stop auto-lock timer
	if (lock_ctx.timer)
		xTimerStop(lock_ctx.timer, 0);

	// Publish status to MQTT
	mqtt_publish_status("LOCKED");
}
