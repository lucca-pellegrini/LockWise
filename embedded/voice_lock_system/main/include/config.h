/* Configuration Management Header */
#pragma once

#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>
#include <stdbool.h>

/* Configuration storage */
extern char wifi_ssid[32];
extern char wifi_password[64];
extern char device_id[64];
extern char backend_url[256];
extern char mqtt_broker_url[256];
extern bool mqtt_heartbeat_enable;
extern int mqtt_heartbeat_interval_sec;
extern int audio_record_timeout_sec;

/* Function prototypes */
void load_config_from_nvs(void);
void update_config(const char *key, const char *value);

#endif /* CONFIG_H */
