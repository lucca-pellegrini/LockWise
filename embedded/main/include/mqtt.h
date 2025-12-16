/* MQTT Management Header */
#pragma once

#ifndef MQTT_H
#define MQTT_H

#include "lock.h"
#include "mqtt_client.h"

/**
 * @brief Handle global do cliente MQTT.
 *
 * Esta variável externa armazena o handle do cliente MQTT usado para comunicação com o broker.
 */
extern esp_mqtt_client_handle_t mqtt_client;

/**
 * @brief Inicializa o cliente MQTT.
 *
 * Esta função configura e inicia o cliente MQTT, conectando-se ao broker especificado na configuração.
 * Assina o tópico específico do dispositivo para receber comandos.
 */
void mqtt_init(void);

/**
 * @brief Publica um status no tópico MQTT do dispositivo.
 *
 * @param status String descrevendo o status atual (ex.: "CONNECTED", "STREAMING").
 *
 * Publica uma mensagem CBOR contendo o evento, uptime e timestamp no tópico lockwise/{device_id}/status.
 */
void mqtt_publish_status(const char *status);

/**
 * @brief Publica um evento de mudança de estado da fechadura via MQTT.
 *
 * @param state Novo estado da fechadura.
 * @param reason Razão da mudança de estado.
 *
 * Publica uma mensagem CBOR detalhada incluindo lock state, reason, uptime e timestamp.
 */
void mqtt_publish_lock_event(lock_state_t state, door_reason_t reason);

/**
 * @brief Tarefa que publica heartbeats periódicos via MQTT.
 *
 * @param pvParameters Parâmetros da tarefa (não usado).
 *
 * Executa em loop, publicando informações completas do estado do dispositivo em intervalos configuráveis.
 */
void mqtt_heartbeat_task(void *pvParameters);

#endif /* MQTT_H */
