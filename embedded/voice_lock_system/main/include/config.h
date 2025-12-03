/* Configuration Management Header */
#pragma once

#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
	char wifi_ssid[32];
	char wifi_password[64];
	char device_id[64];
	char backend_url[256];
	char backend_bearer_token[256];
	char mqtt_broker_url[256];
	char mqtt_broker_password[256];
	bool mqtt_heartbeat_enable;
	int mqtt_heartbeat_interval_sec;
	int audio_record_timeout_sec;
	int lock_timeout_ms;
	char user_pub_key[256]; // Paired user's public key (PEM format)
} config_t;

/* Configuration storage */
extern config_t config;

/* Function prototypes */
void load_config_from_nvs(void);
void update_config(const char *key, const char *value);

#endif /* CONFIG_H */
