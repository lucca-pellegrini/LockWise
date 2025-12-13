/* Lock Control Header */
#pragma once

#include <stdint.h>
#ifndef LOCK_H
#define LOCK_H

/* GPIO Configuration */
#define LOCK_INDICATOR_LED_GPIO 22
#define LOCK_ACTUATOR_GPIO CONFIG_LOCK_GPIO

/* Lock states */
typedef enum { LOCK_STATE_LOCKED, LOCK_STATE_UNLOCKED, LOCK_STATE_AUTHENTICATING } lock_state_t;

/* Door reason enum */
typedef enum {
	DOOR_REASON_BUTTON,
	DOOR_REASON_TIMEOUT,
	DOOR_REASON_MQTT,
	DOOR_REASON_VOICE,
	DOOR_REASON_REBOOT,
	DOOR_REASON_LOCKDOWN,
	DOOR_REASON_SERIAL
} door_reason_t;

/* Blink parameters */
typedef struct {
	uint16_t period_ms;
	uint16_t on_time_ms;
} blink_params_t;

/* Function prototypes */
void lock_init(void);
void unlock_door(door_reason_t reason);
void lock_door(door_reason_t reason);
void toggle_door(door_reason_t reason);
lock_state_t get_lock_state(void);
void blink(void *param);

#endif /* LOCK_H */
