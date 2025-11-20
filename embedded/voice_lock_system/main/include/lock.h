/* Lock Control Header */
#pragma once

#ifndef LOCK_H
#define LOCK_H

/* Lock states */
typedef enum { LOCK_STATE_LOCKED, LOCK_STATE_UNLOCKED, LOCK_STATE_AUTHENTICATING } lock_state_t;

/* Global lock state */
extern lock_state_t current_lock_state;

/* Function prototypes */
void unlock_door(void);
void lock_door(void);

#endif /* LOCK_H */
