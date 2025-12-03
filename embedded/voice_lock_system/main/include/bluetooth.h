/* Bluetooth LE Implementation Header */

#pragma once

#ifndef BLUETOOTH_H
#define BLUETOOTH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Function prototypes */
void bluetooth_init(void);
void bluetooth_enter_pairing_mode(void);
void bluetooth_send_status(const char *status);
bool bluetooth_is_paired(void);
void bluetooth_send_challenge(uint8_t *challenge, size_t len);
bool bluetooth_verify_signature(const uint8_t *challenge, size_t challenge_len, const uint8_t *signature,
				size_t sig_len);

#endif /* BLUETOOTH_H */
