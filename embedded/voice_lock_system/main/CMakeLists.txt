idf_component_register(SRCS
	"src/audio_stream.c"
	"src/config.c"
	"src/lock.c"
	"src/main.c"
	"src/mqtt.c"
	"src/serial.c"
	"src/wifi.c"
	INCLUDE_DIRS "include"
	REQUIRES mqtt esp_peripherals audio_pipeline esp_http_client driver audio_stream mbedtls esp_netif input_key_service
	EMBED_TXTFILES "certs/mqtt_ca.pem")
