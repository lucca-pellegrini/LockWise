/* Lock Control Header */
#pragma once

#ifndef LOCK_H
#define LOCK_H

/* GPIO Configuration */
#define LOCK_INDICATOR_LED_GPIO 22
#define LOCK_ACTUATOR_GPIO CONFIG_LOCK_GPIO

/* Lock states */
typedef enum { LOCK_STATE_LOCKED, LOCK_STATE_UNLOCKED, LOCK_STATE_AUTHENTICATING } lock_state_t;

/* Function prototypes */
void lock_init(void);
void unlock_door(void);
void lock_door(void);

#endif /* LOCK_H */
