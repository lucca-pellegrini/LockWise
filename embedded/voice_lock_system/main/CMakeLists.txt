idf_component_register(SRCS "src/main.c"
                        "src/config.c"
                        "src/wifi.c"
                        "src/mqtt.c"
                        "src/audio.c"
                        "src/http.c"
                        "src/lock.c"
                        "src/serial.c"
                        INCLUDE_DIRS "include"
                        REQUIRES mqtt esp_peripherals audio_pipeline esp_http_client driver audio_stream
                        EMBED_TXTFILES "certs/mqtt_ca.pem")
