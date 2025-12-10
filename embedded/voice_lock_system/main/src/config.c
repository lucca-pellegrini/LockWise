/* Configuration Management Implementation */

#include "config.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "mqtt.h"
#include "nvs.h"
#include "nvs_flash.h"
#include <stdbool.h>
#include <string.h>
#include <strings.h>

static const char *TAG = "LOCKWISE:CONFIG";

/* Configuration storage */
config_t config;

void load_config_from_nvs(void)
{
	nvs_handle_t nvs_handle;
	esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
	int nvs_available = (err == ESP_OK);
	esp_log_level_set(TAG, ESP_LOG_INFO);

	if (!nvs_available) {
		ESP_LOGW(TAG, "NVS unavailable, using all defaults");
	}

	// Load WiFi SSID
	size_t required_size = sizeof(config.wifi_ssid);
	if (nvs_available && nvs_get_str(nvs_handle, "wifi_ssid", config.wifi_ssid, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded wifi_ssid from NVS: %s", config.wifi_ssid);
	} else {
		strcpy(config.wifi_ssid, CONFIG_WIFI_SSID);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "wifi_ssid", config.wifi_ssid);
			ESP_LOGW(TAG, "Using provisioned wifi_ssid and saved to NVS: %s", config.wifi_ssid);
		}
	}

	// Load WiFi Password
	required_size = sizeof(config.wifi_password);
	if (nvs_available && nvs_get_str(nvs_handle, "wifi_pass", config.wifi_password, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded wifi_pass from NVS: [REDACTED]");
	} else {
		strcpy(config.wifi_password, CONFIG_WIFI_PASSWORD);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "wifi_pass", config.wifi_password);
			ESP_LOGW(TAG, "Using provisioned wifi_pass and saved to NVS: [REDACTED]");
		}
	}

	// Load Device ID
	required_size = sizeof(config.device_id);
	if (nvs_available && nvs_get_str(nvs_handle, "device_id", config.device_id, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded device_id from NVS: %s", config.device_id);
	} else {
		strcpy(config.device_id, CONFIG_DEVICE_ID);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "device_id", config.device_id);
			ESP_LOGW(TAG, "Using provisioned device_id and saved to NVS: %s", config.device_id);
		}
	}

	// Load Backend URL
	required_size = sizeof(config.backend_url);
	if (nvs_available && nvs_get_str(nvs_handle, "backend_url", config.backend_url, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded backend_url from NVS: %s", config.backend_url);
	} else {
		strcpy(config.backend_url, CONFIG_BACKEND_URL);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "backend_url", config.backend_url);
			ESP_LOGW(TAG, "Using provisioned backend_url and saved to NVS: %s", config.backend_url);
		}
	}

	// Load Backend Bearer Token
	required_size = sizeof(config.backend_bearer_token);
	if (nvs_available &&
	    nvs_get_str(nvs_handle, "backend_bearer", config.backend_bearer_token, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded backend_bearer_token from NVS: [REDACTED]");
	} else {
		strcpy(config.backend_bearer_token, "");
		if (nvs_available) {
			nvs_set_str(nvs_handle, "backend_bearer", config.backend_bearer_token);
			ESP_LOGW(TAG, "Using default backend_bearer_token and saved to NVS: [REDACTED]");
		}
	}

	// Load MQTT Broker URL
	required_size = sizeof(config.mqtt_broker_url);
	if (nvs_available && nvs_get_str(nvs_handle, "mqtt_broker", config.mqtt_broker_url, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded mqtt_broker_url from NVS: %s", config.mqtt_broker_url);
	} else {
		strcpy(config.mqtt_broker_url, CONFIG_MQTT_BROKER_URL);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "mqtt_broker", config.mqtt_broker_url);
			ESP_LOGW(TAG, "Using provisioned mqtt_broker_url and saved to NVS: %s", config.mqtt_broker_url);
		}
	}

	// Load MQTT Broker Password
	required_size = sizeof(config.mqtt_broker_password);
	if (nvs_available &&
	    nvs_get_str(nvs_handle, "mqtt_pass", config.mqtt_broker_password, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded mqtt_broker_password from NVS: [REDACTED]");
	} else {
		strcpy(config.mqtt_broker_password, "");
		if (nvs_available) {
			nvs_set_str(nvs_handle, "mqtt_pass", config.mqtt_broker_password);
			ESP_LOGW(TAG, "Using default mqtt_broker_password and saved to NVS: [REDACTED]");
		}
	}

	// Load MQTT Heartbeat Enable
	uint8_t enable_val;
	if (nvs_available && nvs_get_u8(nvs_handle, "mqtt_hb_enable", &enable_val) == ESP_OK) {
		config.mqtt_heartbeat_enable = enable_val;
		ESP_LOGI(TAG, "Loaded mqtt_heartbeat_enable from NVS: %d", config.mqtt_heartbeat_enable);
	} else {
		config.mqtt_heartbeat_enable = CONFIG_MQTT_HEARTBEAT_ENABLE;
		if (nvs_available) {
			nvs_set_u8(nvs_handle, "mqtt_hb_enable", config.mqtt_heartbeat_enable);
			ESP_LOGW(TAG, "Using provisioned mqtt_heartbeat_enable and saved to NVS: %d",
				 config.mqtt_heartbeat_enable);
		}
	}

	// Load MQTT Heartbeat Interval
	int32_t interval_val;
	if (nvs_available && nvs_get_i32(nvs_handle, "hb_interval", &interval_val) == ESP_OK) {
		config.mqtt_heartbeat_interval_sec = interval_val;
		ESP_LOGI(TAG, "Loaded mqtt_heartbeat_interval_sec from NVS: %d", config.mqtt_heartbeat_interval_sec);
	} else {
		config.mqtt_heartbeat_interval_sec = CONFIG_MQTT_HEARTBEAT_INTERVAL_SEC;
		if (nvs_available) {
			nvs_set_i32(nvs_handle, "hb_interval", config.mqtt_heartbeat_interval_sec);
			ESP_LOGW(TAG, "Using provisioned mqtt_heartbeat_interval_sec and saved to NVS: %d",
				 config.mqtt_heartbeat_interval_sec);
		}
	}

	// Load Audio Record Timeout
	int32_t timeout_val;
	if (nvs_available && nvs_get_i32(nvs_handle, "audio_timeout", &timeout_val) == ESP_OK) {
		config.audio_record_timeout_sec = timeout_val;
		ESP_LOGI(TAG, "Loaded audio_record_timeout_sec from NVS: %d", config.audio_record_timeout_sec);
	} else {
		config.audio_record_timeout_sec = CONFIG_AUDIO_RECORD_TIMEOUT_SEC;
		if (nvs_available) {
			nvs_set_i32(nvs_handle, "audio_timeout", config.audio_record_timeout_sec);
			ESP_LOGW(TAG, "Using provisioned audio_record_timeout_sec and saved to NVS: %d",
				 config.audio_record_timeout_sec);
		}
	}

	// Load Lock Timeout
	int32_t lock_timeout_val;
	if (nvs_available && nvs_get_i32(nvs_handle, "lock_timeout", &lock_timeout_val) == ESP_OK) {
		config.lock_timeout_ms = lock_timeout_val;
		ESP_LOGI(TAG, "Loaded lock_timeout_ms from NVS: %d", config.lock_timeout_ms);
	} else {
		config.lock_timeout_ms = CONFIG_LOCK_TIMEOUT_MS;
		if (nvs_available) {
			nvs_set_i32(nvs_handle, "lock_timeout", config.lock_timeout_ms);
			ESP_LOGW(TAG, "Using provisioned lock_timeout_ms and saved to NVS: %d", config.lock_timeout_ms);
		}
	}

	// Load User Public Key
	required_size = sizeof(config.user_pub_key);
	if (nvs_available && nvs_get_str(nvs_handle, "user_pub_key", config.user_pub_key, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded user_pub_key from NVS");
	} else {
		strcpy(config.user_pub_key, "");
		if (nvs_available) {
			nvs_set_str(nvs_handle, "user_pub_key", config.user_pub_key);
			ESP_LOGW(TAG, "Using default user_pub_key and saved to NVS");
		}
	}

	// Load pairing_mode
	uint8_t pairing_val = 0;
	if (nvs_available && nvs_get_u8(nvs_handle, "pairing_mode", &pairing_val) == ESP_OK) {
		config.pairing_mode = pairing_val != 0;
		ESP_LOGI(TAG, "Loaded pairing_mode from NVS: %d", config.pairing_mode);
	} else {
		config.pairing_mode = false;
		if (nvs_available) {
			nvs_set_u8(nvs_handle, "pairing_mode", 0);
			ESP_LOGW(TAG, "Using default pairing_mode (false) and saved to NVS");
		}
	}

	if (nvs_available) {
		nvs_commit(nvs_handle);
		nvs_close(nvs_handle);
	}

	ESP_LOGI(TAG, "Device ID: %s", config.device_id);
}

void update_config(const char *key, const char *value)
{
	// Validate key (allow wifi_ssid, wifi_pass, backend_url, backend_bearer, mqtt_broker, mqtt_pass, mqtt_hb_enable, mqtt_hb_interval, audio_timeout, lock_timeout, user_pub_key, pairing_mode)
	if (!strcasecmp(key, "wifi_ssid") || !strcasecmp(key, "wifi_pass") || !strcasecmp(key, "backend_url") ||
	    !strcasecmp(key, "backend_bearer") || !strcasecmp(key, "mqtt_broker") || !strcasecmp(key, "mqtt_pass") ||
	    !strcasecmp(key, "mqtt_hb_enable") || !strcasecmp(key, "mqtt_hb_interval") ||
	    !strcasecmp(key, "audio_timeout") || !strcasecmp(key, "lock_timeout") || !strcasecmp(key, "user_pub_key") ||
	    !strcasecmp(key, "pairing_mode")) {
		nvs_handle_t nvs_handle;
		esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
		if (err == ESP_OK) {
			bool needs_update = false;
			if (!strcasecmp(key, "wifi_ssid")) {
				if (strcmp(config.wifi_ssid, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "wifi_pass")) {
				if (strcmp(config.wifi_password, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "backend_url")) {
				if (strcmp(config.backend_url, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "backend_bearer")) {
				if (strcmp(config.backend_bearer_token, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "mqtt_broker")) {
				if (strcmp(config.mqtt_broker_url, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "mqtt_pass")) {
				if (strcmp(config.mqtt_broker_password, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "mqtt_hb_enable")) {
				uint8_t new_val = atoi(value) ? 1 : 0;
				if (config.mqtt_heartbeat_enable != new_val)
					needs_update = true;
			} else if (!strcasecmp(key, "mqtt_hb_interval")) {
				int32_t new_val = atoi(value);
				if (config.mqtt_heartbeat_interval_sec != new_val)
					needs_update = true;
			} else if (!strcasecmp(key, "audio_timeout")) {
				int32_t new_val = atoi(value);
				if (config.audio_record_timeout_sec != new_val)
					needs_update = true;
			} else if (!strcasecmp(key, "lock_timeout")) {
				int32_t new_val = atoi(value);
				if (config.lock_timeout_ms != new_val)
					needs_update = true;
			} else if (!strcasecmp(key, "user_pub_key")) {
				if (strcmp(config.user_pub_key, value) != 0)
					needs_update = true;
			} else if (!strcasecmp(key, "pairing_mode")) {
				uint8_t new_val = atoi(value) ? 1 : 0;
				if (config.pairing_mode != new_val)
					needs_update = true;
			}

			if (needs_update) {
				esp_err_t set_err = ESP_OK;
				if (!strcasecmp(key, "mqtt_hb_enable")) {
					uint8_t enable_val = atoi(value) ? 1 : 0;
					set_err = nvs_set_u8(nvs_handle, "mqtt_hb_enable", enable_val);
					if (set_err == ESP_OK) {
						config.mqtt_heartbeat_enable = enable_val;
					}
				} else if (!strcasecmp(key, "mqtt_hb_interval")) {
					int32_t interval_val = atoi(value);
					set_err = nvs_set_i32(nvs_handle, "hb_interval", interval_val);
					if (set_err == ESP_OK) {
						config.mqtt_heartbeat_interval_sec = interval_val;
					}
				} else if (!strcasecmp(key, "audio_timeout")) {
					int32_t timeout_val = atoi(value);
					set_err = nvs_set_i32(nvs_handle, "audio_timeout", timeout_val);
					if (set_err == ESP_OK) {
						config.audio_record_timeout_sec = timeout_val;
					}
				} else if (!strcasecmp(key, "lock_timeout")) {
					int32_t lock_timeout_val = atoi(value);
					set_err = nvs_set_i32(nvs_handle, "lock_timeout", lock_timeout_val);
					if (set_err == ESP_OK) {
						config.lock_timeout_ms = lock_timeout_val;
					}
				} else if (!strcasecmp(key, "user_pub_key")) {
					set_err = nvs_set_str(nvs_handle, "user_pub_key", value);
					if (set_err == ESP_OK) {
						strcpy(config.user_pub_key, value);
					}
				} else if (!strcasecmp(key, "pairing_mode")) {
					uint8_t pairing_val = atoi(value) ? 1 : 0;
					esp_err_t set_err = nvs_set_u8(nvs_handle, "pairing_mode", pairing_val);
					if (set_err == ESP_OK) {
						config.pairing_mode = pairing_val;
					}
				} else {
					set_err = nvs_set_str(nvs_handle, key, value);
					if (set_err == ESP_OK) {
						if (!strcasecmp(key, "wifi_ssid")) {
							strcpy(config.wifi_ssid, value);
						} else if (!strcasecmp(key, "wifi_pass")) {
							strcpy(config.wifi_password, value);
						} else if (!strcasecmp(key, "backend_url")) {
							strcpy(config.backend_url, value);
						} else if (!strcasecmp(key, "backend_bearer")) {
							strcpy(config.backend_bearer_token, value);
						} else if (!strcasecmp(key, "mqtt_broker")) {
							strcpy(config.mqtt_broker_url, value);
						} else if (!strcasecmp(key, "mqtt_pass")) {
							strcpy(config.mqtt_broker_password, value);
						} else if (!strcasecmp(key, "user_pub_key")) {
							strcpy(config.user_pub_key, value);
						}
					}
				}
				if (set_err == ESP_OK) {
					esp_err_t commit_err = nvs_commit(nvs_handle);
					if (commit_err == ESP_OK) {
						ESP_LOGI(TAG, "Updated config %s in NVS", key);
						mqtt_publish_status("CONFIG_UPDATED");
					} else {
						ESP_LOGE(TAG, "Failed to commit config %s to NVS: %s", key,
							 esp_err_to_name(commit_err));
						mqtt_publish_status("COMMIT_CONFIG_FAILED");
					}
				} else {
					ESP_LOGE(TAG, "Failed to set config %s in NVS: %s", key,
						 esp_err_to_name(set_err));
					mqtt_publish_status("UPDATE_CONFIG_FAILED");
				}
			} else {
				ESP_LOGI(TAG, "Config %s already has the same value, skipping NVS update", key);
			}
			nvs_close(nvs_handle);
		} else {
			ESP_LOGE(TAG, "Failed to open NVS for config update: %s", esp_err_to_name(err));
			mqtt_publish_status("NVM_OPEN_FAILED");
		}
	} else {
		ESP_LOGW(TAG, "Invalid config key: %s", key);
		mqtt_publish_status("INVALID_CONFIG_KEY");
	}
}
