/* Configuration Management Header */

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

/* Function prototypes */
void load_config_from_nvs(void);
void update_config(const char *key, const char *value);

#endif /* CONFIG_H */