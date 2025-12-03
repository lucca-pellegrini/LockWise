/* WiFi Management Implementation */

#include "wifi.h"
#include "config.h"
#include <string.h>
#include "esp_log.h"
#include "esp_peripherals.h"
#include "periph_wifi.h"

#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(4, 1, 0))
#include "esp_netif.h"
#else
#include "tcpip_adapter.h"
#endif

static const char *TAG = "LOCKWISE:WIFI";

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
