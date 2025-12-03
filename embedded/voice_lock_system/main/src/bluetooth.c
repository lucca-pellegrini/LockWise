/* Bluetooth LE Implementation */

#include "bluetooth.h"
#include "config.h"
#include "lock.h"
#include "esp_log.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gatts_api.h"
#include "esp_bt_device.h"
#include "esp_gap_ble_api.h"
#include "esp_http_client.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/ecdsa.h"
#include "mbedtls/pk.h"
#include "mbedtls/sha256.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include <string.h>
#include <stdlib.h>

static const char *TAG = "LOCKWISE:BLE";

static bool pairing_mode = false;
static uint16_t gatts_if;
static uint16_t conn_id;
static esp_gatt_srvc_id_t pairing_service_id;
static esp_gatt_srvc_id_t command_service_id;

// UUIDs
static const uint16_t pairing_service_uuid = 0xFF00;
static const uint16_t pub_key_char_uuid = 0xFF01;
static const uint16_t user_id_char_uuid = 0xFF02;
static const uint16_t command_service_uuid = 0xFF10;
static const uint16_t challenge_char_uuid = 0xFF11;
static const uint16_t signature_char_uuid = 0xFF12;
static const uint16_t command_char_uuid = 0xFF13;

// Characteristics
static esp_gatts_attr_db_t gatt_db[] = {
	// Pairing service
	[0] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&pairing_service_uuid, ESP_GATT_PERM_READ, sizeof(pairing_service_uuid),
		  sizeof(pairing_service_uuid), (uint8_t *)&pairing_service_uuid } },
	[1] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&pub_key_char_uuid, ESP_GATT_PERM_WRITE, 256, 0, NULL } },
	[2] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&user_id_char_uuid, ESP_GATT_PERM_WRITE, 64, 0, NULL } },

	// Command service
	[3] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&command_service_uuid, ESP_GATT_PERM_READ, sizeof(command_service_uuid),
		  sizeof(command_service_uuid), (uint8_t *)&command_service_uuid } },
	[4] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&challenge_char_uuid, ESP_GATT_PERM_READ, 32, 0, NULL } },
	[5] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&signature_char_uuid, ESP_GATT_PERM_WRITE, 64, 0, NULL } },
	[6] = { { ESP_GATT_AUTO_RSP },
		{ ESP_UUID_LEN_16, (uint8_t *)&command_char_uuid, ESP_GATT_PERM_WRITE, 32, 0, NULL } },
};

static uint8_t challenge[32];
static bool challenge_sent = false;

static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param);
static void gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param);
static void send_user_id_to_backend(const char *user_id);
static void generate_challenge(void);

void bluetooth_init(void)
{
	esp_log_level_set(TAG, ESP_LOG_INFO);
	ESP_LOGI(TAG, "Initializing Bluetooth LE");

	// Initialize BT controller
	esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
	esp_bt_controller_init(&bt_cfg);
	esp_bt_controller_enable(ESP_BT_MODE_BLE);

	// Initialize Bluedroid
	esp_bluedroid_init();
	esp_bluedroid_enable();

	// Set device name
	esp_ble_gap_set_device_name("LockWise_BLE");

	// Register callbacks
	esp_ble_gap_register_callback(gap_event_handler);
	esp_ble_gatts_register_callback(gatts_event_handler);

	// TODO: Create GATT database
	// esp_ble_gatts_create_attr_tab(gatt_db, sizeof(gatt_db) / sizeof(gatt_db[0]), 0);

	ESP_LOGI(TAG, "Bluetooth LE initialized");
}

void bluetooth_enter_pairing_mode(void)
{
	pairing_mode = true;
	ESP_LOGI(TAG, "Entered BLE pairing mode");

	// Start advertising
	esp_ble_gap_start_advertising(&(esp_ble_adv_params_t){
		.adv_int_min = 0x20,
		.adv_int_max = 0x40,
		.adv_type = ADV_TYPE_IND,
		.own_addr_type = BLE_ADDR_TYPE_PUBLIC,
		.channel_map = ADV_CHNL_ALL,
		.adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
	});
}

void bluetooth_send_status(const char *status)
{
	ESP_LOGI(TAG, "BLE status: %s", status);
	// TODO: Send via GATT notification if connected
}

bool bluetooth_is_paired(void)
{
	return strlen(config.user_pub_key) > 0;
}

void bluetooth_send_challenge(uint8_t *chal, size_t len)
{
	if (len != 32)
		return;
	memcpy(challenge, chal, 32);
	challenge_sent = true;
	// Update characteristic value
	esp_ble_gatts_set_attr_value(4, 32, challenge); // attr_handle for challenge
}

bool bluetooth_verify_signature(const uint8_t *chal, size_t challenge_len, const uint8_t *signature, size_t sig_len)
{
	if (strlen(config.user_pub_key) == 0)
		return false;

	mbedtls_pk_context pk;
	mbedtls_pk_init(&pk);

	int ret = mbedtls_pk_parse_public_key(&pk, (const unsigned char *)config.user_pub_key,
					      strlen(config.user_pub_key) + 1);
	if (ret != 0) {
		ESP_LOGE(TAG, "Failed to parse public key: %d", ret);
		mbedtls_pk_free(&pk);
		return false;
	}

	// Compute SHA256 of challenge
	uint8_t hash[32];
	mbedtls_sha256(chal, challenge_len, hash, 0);

	// Verify signature
	ret = mbedtls_pk_verify(&pk, MBEDTLS_MD_SHA256, hash, sizeof(hash), signature, sig_len);
	mbedtls_pk_free(&pk);

	return ret == 0;
}

static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param)
{
	switch (event) {
	case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
		if (param->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
			ESP_LOGI(TAG, "Advertising started");
		} else {
			ESP_LOGE(TAG, "Advertising failed");
		}
		break;
	default:
		break;
	}
}

static void gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param)
{
	switch (event) {
	case ESP_GATTS_REG_EVT:
		ESP_LOGI(TAG, "GATT registered, app_id %04x, status %d", param->reg.app_id, param->reg.status);
		break;
	case ESP_GATTS_CREATE_EVT:
		ESP_LOGI(TAG, "Service created, status %d, handle %d", param->create.status,
			 param->create.service_handle);
		break;
	case ESP_GATTS_CONNECT_EVT:
		ESP_LOGI(TAG, "Connected, conn_id %d", param->connect.conn_id);
		conn_id = param->connect.conn_id;
		break;
	case ESP_GATTS_DISCONNECT_EVT:
		ESP_LOGI(TAG, "Disconnected, conn_id %d", param->disconnect.conn_id);
		if (pairing_mode) {
			esp_ble_gap_start_advertising(NULL); // Restart advertising
		}
		break;
	case ESP_GATTS_WRITE_EVT:
		ESP_LOGI(TAG, "Write event, attr_handle %d, len %d", param->write.handle, param->write.len);
		if (pairing_mode) {
			// Handle pairing writes
			static char pub_key[256] = { 0 };
			static char user_id[64] = { 0 };
			if (param->write.handle == 1) { // pub_key char
				strncpy(pub_key, (char *)param->write.value, param->write.len);
				pub_key[param->write.len] = '\0';
			} else if (param->write.handle == 2) { // user_id char
				strncpy(user_id, (char *)param->write.value, param->write.len);
				user_id[param->write.len] = '\0';
				// Pairing complete
				strcpy(config.user_pub_key, pub_key);
				update_config("user_pub_key", pub_key);
				send_user_id_to_backend(user_id);
				pairing_mode = false;
				esp_ble_gap_stop_advertising();
				ESP_LOGI(TAG, "Pairing complete with user %s", user_id);
			}
		} else {
			// Handle command writes
			static uint8_t signature[64];
			static char command[32];
			if (param->write.handle == 5) { // signature char
				memcpy(signature, param->write.value, param->write.len);
			} else if (param->write.handle == 6) { // command char
				strncpy(command, (char *)param->write.value, param->write.len);
				command[param->write.len] = '\0';
				// Verify signature
				if (bluetooth_verify_signature(challenge, sizeof(challenge), signature, 64)) {
					ESP_LOGI(TAG, "Signature verified, executing command: %s", command);
					if (strcmp(command, "UNLOCK") == 0) {
						unlock_door();
					} else if (strcmp(command, "LOCK") == 0) {
						lock_door();
					}
				} else {
					ESP_LOGW(TAG, "Invalid signature");
				}
				// Generate new challenge
				generate_challenge();
			}
		}
		break;
	case ESP_GATTS_READ_EVT:
		if (param->read.handle == 4 && challenge_sent) { // challenge char
			esp_gatt_rsp_t rsp = {
				.attr_value.handle = param->read.handle,
				.attr_value.len = 32,
			};
			memcpy(rsp.attr_value.value, challenge, 32);
			esp_ble_gatts_send_response(gatts_if, param->read.conn_id, param->read.trans_id, ESP_GATT_OK,
						    &rsp);
		}
		break;
	default:
		break;
	}
}

static void send_user_id_to_backend(const char *user_id)
{
	char url[512];
	snprintf(url, sizeof(url), "%s/api/devices/%s/pair", config.backend_url, config.device_id);

	esp_http_client_config_t config_http = {
		.url = url,
		.method = HTTP_METHOD_POST,
		.timeout_ms = 10000,
	};

	esp_http_client_handle_t client = esp_http_client_init(&config_http);
	char auth_header[512];
	snprintf(auth_header, sizeof(auth_header), "Bearer %s", config.backend_bearer_token);
	esp_http_client_set_header(client, "Authorization", auth_header);
	esp_http_client_set_header(client, "Content-Type", "application/json");

	char post_data[128];
	snprintf(post_data, sizeof(post_data), "{\"user_id\":\"%s\"}", user_id);
	esp_http_client_set_post_field(client, post_data, strlen(post_data));

	esp_err_t err = esp_http_client_perform(client);
	if (err == ESP_OK) {
		ESP_LOGI(TAG, "User ID sent to backend");
	} else {
		ESP_LOGE(TAG, "Failed to send user ID: %s", esp_err_to_name(err));
	}
	esp_http_client_cleanup(client);
}

static void generate_challenge(void)
{
	esp_fill_random(challenge, sizeof(challenge));
	challenge_sent = false;
}
