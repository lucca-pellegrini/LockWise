/* WiFi Management Implementation */

#include "config.h"
#include "esp_log.h"
#include "esp_peripherals.h"
#include "lwip/sockets.h"
#include "periph_wifi.h"
#include "wifi.h"
#include <string.h>
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "nvs_flash.h"
#include "lwip/ip4_addr.h"
#include <ctype.h>
#include <stdio.h>
#include "esp_system.h"
#include "esp_mac.h"

#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(4, 1, 0))
#include "esp_netif.h"
#else
#include "tcpip_adapter.h"
#endif

static const char *TAG = "LOCKWISE:WIFI";

static int pairing_sock = -1;

static void handle_pairing_client(int client_sock);
static void parse_configure_request(const char *request, char *wifi_ssid, char *wifi_pass, char *user_id);

void wifi_init(void)
{
	esp_log_level_set(TAG, ESP_LOG_INFO);
	ESP_LOGI(TAG, "Initializing WiFi, SSID: %s", config.wifi_ssid);

	esp_periph_config_t periph_cfg = DEFAULT_ESP_PERIPH_SET_CONFIG();
	esp_periph_set_handle_t set = esp_periph_set_init(&periph_cfg);

	periph_wifi_cfg_t wifi_cfg = {
		.wifi_config.sta.ssid = {},
		.wifi_config.sta.password = {},
	};

	// Copy SSID and password to the config
	strncpy((char *)wifi_cfg.wifi_config.sta.ssid, config.wifi_ssid, sizeof(wifi_cfg.wifi_config.sta.ssid));
	strncpy((char *)wifi_cfg.wifi_config.sta.password, config.wifi_password,
		sizeof(wifi_cfg.wifi_config.sta.password));

	esp_periph_handle_t wifi_handle = periph_wifi_init(&wifi_cfg);
	esp_periph_start(set, wifi_handle);
	esp_err_t wifi_result = periph_wifi_wait_for_connected(wifi_handle, 30000); // 30 second timeout
	if (wifi_result != ESP_OK) {
		ESP_LOGE(TAG, "WiFi connection failed within timeout, continuing without WiFi");
		return;
	}

	ESP_LOGI(TAG, "WiFi connected successfully");

	// Get and log IP address
	esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
	if (netif) {
		esp_netif_ip_info_t ip_info;
		esp_netif_get_ip_info(netif, &ip_info);
		ESP_LOGI(TAG, "IP Address: " IPSTR, IP2STR(&ip_info.ip));
		ESP_LOGI(TAG, "Gateway: " IPSTR, IP2STR(&ip_info.gw));
		ESP_LOGI(TAG, "Netmask: " IPSTR, IP2STR(&ip_info.netmask));

		// Set static DNS servers
		esp_netif_dns_info_t dns_main = { .ip = { .u_addr = { .ip4 = { .addr = 0x01010101 } } } };
		esp_netif_dns_info_t dns_backup = { .ip = { .u_addr = { .ip4 = { .addr = 0x08080808 } } } };
		esp_netif_set_dns_info(netif, ESP_NETIF_DNS_MAIN, &dns_main);
		esp_netif_set_dns_info(netif, ESP_NETIF_DNS_BACKUP, &dns_backup);

		// Get and log DNS servers
		esp_netif_dns_info_t dns_info;
		esp_netif_get_dns_info(netif, ESP_NETIF_DNS_MAIN, &dns_info);
		ESP_LOGI(TAG, "DNS Server: " IPSTR, IP2STR(&dns_info.ip.u_addr.ip4));
		esp_netif_get_dns_info(netif, ESP_NETIF_DNS_BACKUP, &dns_info);
		ESP_LOGI(TAG, "DNS Backup: " IPSTR, IP2STR(&dns_info.ip.u_addr.ip4));
	}
}

static void wifi_init_ap(void)
{
	esp_log_level_set(TAG, ESP_LOG_INFO);
	ESP_LOGI(TAG, "Initializing WiFi in AP mode for pairing");

	// Generate AP password from device_id (first 8 chars, formatted as XXXX-XXXX)
	char ap_password[10];
	strncpy(ap_password, config.device_id, 4);
	ap_password[4] = '-';
	strncpy(ap_password + 5, config.device_id + 4, 4);
	ap_password[9] = '\0';
	for (int i = 0; i < 9; i++)
		// Uppercase the password
		for (int i = 0; i < 9; i++) {
			ap_password[i] = toupper((unsigned char)ap_password[i]);
		}

	// Generate SSID with MAC-derived identifier
	uint8_t mac[6];
	esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
	char ssid[32];
	snprintf(ssid, sizeof(ssid), "LockWise-%02X%02X%02X%02X", mac[2], mac[3], mac[4], mac[5]);

	// Make sure netif and event loop are initialized (no-op if already done)
	esp_err_t ret = esp_netif_init();
	if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
		ESP_LOGE(TAG, "esp_netif_init failed: %s", esp_err_to_name(ret));
		return;
	}
	ret = esp_event_loop_create_default();
	if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
		ESP_LOGE(TAG, "esp_event_loop_create_default failed: %s", esp_err_to_name(ret));
		return;
	}

	// Create default AP netif (recommended helper) — it registers default wifi AP handlers
	esp_netif_t *ap_netif = esp_netif_create_default_wifi_ap();
	if (ap_netif == NULL) {
		ESP_LOGE(TAG, "esp_netif_create_default_wifi_ap() failed");
		return;
	}

	// Set static IP for AP before starting WiFi
	esp_netif_ip_info_t ap_ip_info = {
		.ip = { .addr = ESP_IP4TOADDR(192, 168, 4, 1) },
		.netmask = { .addr = ESP_IP4TOADDR(255, 255, 255, 0) },
		.gw = { .addr = ESP_IP4TOADDR(192, 168, 4, 1) },
	};
	ret = esp_netif_set_ip_info(ap_netif, &ap_ip_info);
	if (ret != ESP_OK) {
		ESP_LOGE(TAG, "esp_netif_set_ip_info failed: %s", esp_err_to_name(ret));
		// not fatal for debugging, continue
	}

	// Initialize WiFi driver
	wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
	ret = esp_wifi_init(&cfg);
	if (ret != ESP_OK) {
		ESP_LOGE(TAG, "esp_wifi_init failed: %s", esp_err_to_name(ret));
		return;
	}

	ret = esp_wifi_set_mode(WIFI_MODE_AP);
	if (ret != ESP_OK) {
		ESP_LOGE(TAG, "esp_wifi_set_mode failed: %s", esp_err_to_name(ret));
		return;
	}

	wifi_config_t wifi_config = {
		.ap = { .ssid = "",
			.password = "",
			.ssid_len = 0,
			.channel = 1,
			.authmode = WIFI_AUTH_WPA2_PSK,
			.max_connection = 4,
			.ssid_hidden = 0 },
	};
	strncpy((char *)wifi_config.ap.ssid, ssid, sizeof(wifi_config.ap.ssid));
	wifi_config.ap.ssid_len = strlen(ssid);
	strncpy((char *)wifi_config.ap.password, ap_password, sizeof(wifi_config.ap.password));
	ret = esp_wifi_set_config(WIFI_IF_AP, &wifi_config);
	if (ret != ESP_OK) {
		ESP_LOGE(TAG, "esp_wifi_set_config failed: %s", esp_err_to_name(ret));
		return;
	}

	ret = esp_wifi_start();
	if (ret != ESP_OK) {
		ESP_LOGE(TAG, "esp_wifi_start failed: %s", esp_err_to_name(ret));
		return;
	}

	// Start DHCP server for AP netif
	ret = esp_netif_dhcps_start(ap_netif);
	if (ret == ESP_OK) {
		ESP_LOGI(TAG, "DHCP server started successfully");
	} else {
		ESP_LOGE(TAG, "Failed to start DHCP server: %s", esp_err_to_name(ret));
	}

	// Log AP IP info
	esp_netif_ip_info_t ip_info;
	if (esp_netif_get_ip_info(ap_netif, &ip_info) == ESP_OK) {
		ESP_LOGI(TAG, "WiFi AP started: SSID=%s, Password=%s", ssid, ap_password);
		ESP_LOGI(TAG, "AP IP: " IPSTR ", GW: " IPSTR ", Netmask: " IPSTR, IP2STR(&ip_info.ip),
			 IP2STR(&ip_info.gw), IP2STR(&ip_info.netmask));
	}
}

void start_pairing_server(void)
{
	// Initialize WiFi in AP mode
	wifi_init_ap();

	struct sockaddr_in server_addr;
	pairing_sock = socket(AF_INET, SOCK_STREAM, 0);
	if (pairing_sock < 0) {
		ESP_LOGE(TAG, "Failed to create socket");
		return;
	}

	server_addr.sin_family = AF_INET;
	server_addr.sin_port = htons(80);
	server_addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if (bind(pairing_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
		ESP_LOGE(TAG, "Failed to bind socket");
		close(pairing_sock);
		pairing_sock = -1;
		return;
	}

	if (listen(pairing_sock, 1) < 0) {
		ESP_LOGE(TAG, "Failed to listen on socket");
		close(pairing_sock);
		pairing_sock = -1;
		return;
	}

	ESP_LOGI(TAG, "Pairing server started on port 80");

	// Accept connections in a loop
	for (;;) {
		struct sockaddr_in client_addr;
		socklen_t client_addr_len = sizeof(client_addr);
		int client_sock = accept(pairing_sock, (struct sockaddr *)&client_addr, &client_addr_len);
		if (client_sock >= 0) {
			ESP_LOGI(TAG, "Client connected");
			handle_pairing_client(client_sock);
			close(client_sock);
		}
	}
}

static void handle_pairing_client(int client_sock)
{
	char buffer[1024];
	int len = recv(client_sock, buffer, sizeof(buffer) - 1, 0);
	if (len <= 0) {
		return;
	}
	buffer[len] = '\0';

	// Simple HTTP request parsing
	if (strstr(buffer, "POST /configure")) {
		char wifi_ssid[32] = "";
		char wifi_pass[64] = "";
		char user_id[256] = "";

		parse_configure_request(buffer, wifi_ssid, wifi_pass, user_id);

		if (strlen(wifi_ssid) > 0 && strlen(wifi_pass) > 0 && strlen(user_id) > 0) {
			// Store configuration
			update_config("wifi_ssid", wifi_ssid);
			update_config("wifi_pass", wifi_pass);
			update_config("user_id", user_id);
			// pairing_mode is already set to 0 at the start of pairing mode

			// Send success response (204 No Content)
			const char *response = "HTTP/1.1 204 No Content\r\n\r\n";
			send(client_sock, response, strlen(response), 0);

			ESP_LOGI(TAG, "Configuration stored: user_id=%s, ssid=%s, rebooting...", user_id, wifi_ssid);
			vTaskDelay(pdMS_TO_TICKS(1000));
			esp_restart();
		} else {
			const char *response =
				"HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid configuration\n";
			send(client_sock, response, strlen(response), 0);
		}
	} else {
		const char *response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot found\n";
		send(client_sock, response, strlen(response), 0);
	}
}

static void parse_configure_request(const char *request, char *wifi_ssid, char *wifi_pass, char *user_id)
{
	// Find plain text body after HTTP headers
	const char *body_start = strstr(request, "\r\n\r\n");
	if (!body_start)
		return;
	body_start += 4;

	// Parse three lines: user_id\nwifi_ssid\nwifi_password
	char line[256];
	int line_num = 0;
	const char *ptr = body_start;

	while (*ptr && line_num < 3) {
		// Extract one line
		const char *line_end = strchr(ptr, '\n');
		if (!line_end) {
			// Last line without newline
			strncpy(line, ptr, sizeof(line) - 1);
			line[sizeof(line) - 1] = '\0';
		} else {
			size_t len = line_end - ptr;
			if (len >= sizeof(line))
				len = sizeof(line) - 1;
			strncpy(line, ptr, len);
			line[len] = '\0';
			ptr = line_end + 1;
		}

		// Remove trailing \r if present
		char *crlf = strchr(line, '\r');
		if (crlf)
			*crlf = '\0';

		// Store based on line number
		switch (line_num) {
			case 0: // user_id
				strncpy(user_id, line, 255);
				user_id[255] = '\0';
				break;
			case 1: // wifi_ssid
				strncpy(wifi_ssid, line, 31);
				wifi_ssid[31] = '\0';
				break;
			case 2: // wifi_password
				strncpy(wifi_pass, line, 63);
				wifi_pass[63] = '\0';
				break;
		}
		line_num++;
	}
}
