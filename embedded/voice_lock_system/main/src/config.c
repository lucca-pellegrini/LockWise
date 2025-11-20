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
char wifi_ssid[32];
char wifi_password[64];
char device_id[64];
char backend_url[256];
char mqtt_broker_url[256];

void load_config_from_nvs(void)
{
	nvs_handle_t nvs_handle;
	esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
	int nvs_available = (err == ESP_OK);

	if (!nvs_available) {
		ESP_LOGW(TAG, "NVS unavailable, using all defaults");
	}

	// Load WiFi SSID
	size_t required_size = sizeof(wifi_ssid);
	if (nvs_available && nvs_get_str(nvs_handle, "wifi_ssid", wifi_ssid, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded wifi_ssid from NVS: %s", wifi_ssid);
	} else {
		strcpy(wifi_ssid, CONFIG_WIFI_SSID);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "wifi_ssid", wifi_ssid);
			ESP_LOGW(TAG, "Using provisioned wifi_ssid and saved to NVS: %s", wifi_ssid);
		}
	}

	// Load WiFi Password
	required_size = sizeof(wifi_password);
	if (nvs_available && nvs_get_str(nvs_handle, "wifi_pass", wifi_password, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded wifi_pass from NVS: [REDACTED]");
	} else {
		strcpy(wifi_password, CONFIG_WIFI_PASSWORD);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "wifi_pass", wifi_password);
			ESP_LOGW(TAG, "Using provisioned wifi_pass and saved to NVS: [REDACTED]");
		}
	}

	// Load Device ID
	required_size = sizeof(device_id);
	if (nvs_available && nvs_get_str(nvs_handle, "device_id", device_id, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded device_id from NVS: %s", device_id);
	} else {
		strcpy(device_id, CONFIG_DEVICE_ID);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "device_id", device_id);
			ESP_LOGW(TAG, "Using provisioned device_id and saved to NVS: %s", device_id);
		}
	}

	// Load Backend URL
	required_size = sizeof(backend_url);
	if (nvs_available && nvs_get_str(nvs_handle, "backend_url", backend_url, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded backend_url from NVS: %s", backend_url);
	} else {
		strcpy(backend_url, CONFIG_BACKEND_URL);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "backend_url", backend_url);
			ESP_LOGW(TAG, "Using provisioned backend_url and saved to NVS: %s", backend_url);
		}
	}

	// Load MQTT Broker URL
	required_size = sizeof(mqtt_broker_url);
	if (nvs_available && nvs_get_str(nvs_handle, "mqtt_broker", mqtt_broker_url, &required_size) == ESP_OK) {
		ESP_LOGI(TAG, "Loaded mqtt_broker_url from NVS: %s", mqtt_broker_url);
	} else {
		strcpy(mqtt_broker_url, CONFIG_MQTT_BROKER_URL);
		if (nvs_available) {
			nvs_set_str(nvs_handle, "mqtt_broker", mqtt_broker_url);
			ESP_LOGW(TAG, "Using provisioned mqtt_broker_url and saved to NVS: %s", mqtt_broker_url);
		}
	}

	if (nvs_available) {
		nvs_commit(nvs_handle);
		nvs_close(nvs_handle);
	}

	ESP_LOGI(TAG, "Device ID: %s", device_id);
}

void update_config(const char *key, const char *value)
{
	// Validate key (allow wifi_ssid, wifi_pass, backend_url, mqtt_broker)
	if (!strcasecmp(key, "wifi_ssid") || !strcasecmp(key, "wifi_pass") || !strcasecmp(key, "backend_url") ||
	    !strcasecmp(key, "mqtt_broker")) {
		nvs_handle_t nvs_handle;
		esp_err_t err = nvs_open("voice_lock", NVS_READWRITE, &nvs_handle);
		if (err == ESP_OK) {
			nvs_set_str(nvs_handle, key, value);
			nvs_commit(nvs_handle);
			nvs_close(nvs_handle);
			ESP_LOGI(TAG, "Updated config %s in NVS", key);
		} else {
			ESP_LOGE(TAG, "Failed to open NVS for config update: %s", esp_err_to_name(err));
		}
	} else {
		ESP_LOGW(TAG, "Invalid config key: %s", key);
	}
}