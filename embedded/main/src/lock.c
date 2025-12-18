/* Lock Control Implementation */

#include "config.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/timers.h"
#include "lock.h"
#include "mqtt.h"
#include <stdint.h>

static const char *TAG = "\033[1mLOCKWISE:\033[93mLOCK";

/**
 * @brief Estrutura de contexto para gerenciamento da fechadura.
 *
 * Mantém o estado da fechadura, mutex para sincronização e timer de auto-trancamento.
 */
typedef struct {
	lock_state_t state; /**< Estado atual da fechadura */
	SemaphoreHandle_t mutex; /**< Mutex para proteger acesso ao contexto */
	TimerHandle_t timer; /**< Timer para trancamento automático */
} lock_context_t;

/** @brief Instância singleton do contexto da fechadura */
static lock_context_t lock_ctx;

void lock_init(void)
{
	gpio_set_level(LOCK_ACTUATOR_GPIO, 0);
	esp_log_level_set(TAG, ESP_LOG_INFO);

	lock_ctx = (lock_context_t){
		.state = LOCK_STATE_LOCKED,
		.mutex = xSemaphoreCreateMutex(),
		.timer = NULL,
	};
}

/**
 * @brief Callback do timer de trancamento automático.
 *
 * @param xTimer Handle do timer que expirou.
 *
 * Chamado quando o timer de auto-trancamento expira, trancando a fechadura automaticamente.
 */
static void lock_timeout_callback(TimerHandle_t xTimer)
{
	ESP_LOGI(TAG, "Lock timeout reached, auto-locking door");
	lock_door(DOOR_REASON_TIMEOUT);
}

/* Blink Task */
void blink(void *param)
{
	blink_params_t *blink_params = (blink_params_t *)param;
	uint16_t period_ms = blink_params->period_ms;
	uint16_t on_time_ms = blink_params->on_time_ms;
	uint16_t off_time_ms = period_ms - on_time_ms;

	for (;;) {
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 1);
		vTaskDelay(pdMS_TO_TICKS(on_time_ms));
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);
		vTaskDelay(pdMS_TO_TICKS(off_time_ms));
	}
}

void unlock_door(door_reason_t reason)
{
	xSemaphoreTake(lock_ctx.mutex, portMAX_DELAY);

	if (lock_ctx.state != LOCK_STATE_UNLOCKED) {
		ESP_LOGW(TAG, "Unlocking door");
		lock_ctx.state = LOCK_STATE_UNLOCKED;

		// Unlock the lock actuator
		gpio_set_level(LOCK_ACTUATOR_GPIO, 1);

		// Publish status to MQTT
		mqtt_publish_lock_event(LOCK_STATE_UNLOCKED, reason);
	} else {
		ESP_LOGI(TAG, "Door already unlocked, restarting auto-lock timer");
	}

	// Start or restart auto-lock timer
	if (!lock_ctx.timer)
		lock_ctx.timer = xTimerCreate("LockTimer", pdMS_TO_TICKS(config.lock_timeout_ms), pdFALSE, NULL,
					      lock_timeout_callback);
	else
		xTimerStop(lock_ctx.timer, 0);
	xTimerStart(lock_ctx.timer, 0);

	xSemaphoreGive(lock_ctx.mutex);
}

void lock_door(door_reason_t reason)
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
	gpio_set_level(LOCK_ACTUATOR_GPIO, 0);

	// Stop auto-lock timer
	if (lock_ctx.timer)
		xTimerStop(lock_ctx.timer, 0);

	// Publish status to MQTT
	mqtt_publish_lock_event(LOCK_STATE_LOCKED, reason);
}

void toggle_door(door_reason_t reason)
{
	if (lock_ctx.state == LOCK_STATE_LOCKED)
		unlock_door(reason);
	else
		lock_door(reason);
}

lock_state_t get_lock_state(void)
{
	return lock_ctx.state;
}
