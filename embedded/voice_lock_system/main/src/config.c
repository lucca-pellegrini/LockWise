/* Configuration Management Implementation */

#include "config.h"
#include "esp_system.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"

static const char *TAG = "LOCKWISE_CONFIG";

/* Configuration storage */
config_t config;

void load_config_from_nvs(void)
{
	nvs_handle_t nvs_handle;
	esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
	int nvs_available = (err == ESP_OK);

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

	if (nvs_available) {
		nvs_commit(nvs_handle);
		nvs_close(nvs_handle);
	}

	ESP_LOGI(TAG, "Device ID: %s", config.device_id);
}

void update_config(const char *key, const char *value)
{
	// Validate key (allow wifi_ssid, wifi_pass, backend_url, mqtt_broker, mqtt_hb_enable, mqtt_hb_interval, audio_timeout)
	if (!strcasecmp(key, "wifi_ssid") || !strcasecmp(key, "wifi_pass") || !strcasecmp(key, "backend_url") ||
	    !strcasecmp(key, "mqtt_broker") || !strcasecmp(key, "mqtt_hb_enable") ||
	    !strcasecmp(key, "mqtt_hb_interval") || !strcasecmp(key, "audio_timeout")) {
		nvs_handle_t nvs_handle;
		esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
		if (err == ESP_OK) {
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
			} else {
				set_err = nvs_set_str(nvs_handle, key, value);
			}
			if (set_err == ESP_OK) {
				esp_err_t commit_err = nvs_commit(nvs_handle);
				if (commit_err == ESP_OK) {
					ESP_LOGI(TAG, "Updated config %s in NVS", key);
				} else {
					ESP_LOGE(TAG, "Failed to commit config %s to NVS: %s", key,
						 esp_err_to_name(commit_err));
				}
			} else {
				ESP_LOGE(TAG, "Failed to set config %s in NVS: %s", key, esp_err_to_name(set_err));
			}
			nvs_close(nvs_handle);
		} else {
			ESP_LOGE(TAG, "Failed to open NVS for config update: %s", esp_err_to_name(err));
		}
	} else {
		ESP_LOGW(TAG, "Invalid config key: %s", key);
	}
}
