/* MQTT Management Header */
#pragma once

#ifndef MQTT_H
#define MQTT_H

#include "mqtt_client.h"

/* External MQTT client handle */
extern esp_mqtt_client_handle_t mqtt_client;

/* Function prototypes */
void mqtt_init(void);
void mqtt_publish_status(const char *status);
void mqtt_heartbeat_task(void *pvParameters);

#endif /* MQTT_H */
