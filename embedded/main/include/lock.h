/* Lock Control Header */
#pragma once

#include <stdint.h>
#ifndef LOCK_H
#define LOCK_H

/** @brief Pino GPIO para o LED indicador da fechadura */
#define LOCK_INDICATOR_LED_GPIO 22

/** @brief Pino GPIO para o atuador da fechadura (configurável via menuconfig) */
#define LOCK_ACTUATOR_GPIO CONFIG_LOCK_GPIO

/**
 * @brief Estados possíveis da fechadura.
 */
typedef enum {
	LOCK_STATE_LOCKED, /**< Fechadura está trancada */
	LOCK_STATE_UNLOCKED, /**< Fechadura está destrancada */
	LOCK_STATE_AUTHENTICATING /**< Fechadura está em processo de autenticação */
} lock_state_t;

/**
 * @brief Razões para mudança de estado da fechadura.
 */
typedef enum {
	DOOR_REASON_BUTTON, /**< Ação manual via botão de toque */
	DOOR_REASON_TIMEOUT, /**< Trancamento automático por timeout */
	DOOR_REASON_MQTT, /**< Comando via MQTT */
	DOOR_REASON_VOICE, /**< Autenticação por voz */
	DOOR_REASON_REBOOT, /**< Reinicialização do sistema */
	DOOR_REASON_LOCKDOWN, /**< Bloqueio de emergência */
	DOOR_REASON_SERIAL /**< Comando via interface serial */
} door_reason_t;

/**
 * @brief Parâmetros para controle do piscar do LED.
 */
typedef struct {
	uint16_t period_ms; /**< Período total do ciclo de piscar em ms */
	uint16_t on_time_ms; /**< Tempo em que o LED fica aceso em ms */
} blink_params_t;

/**
 * @brief Inicializa o controle da fechadura.
 *
 * Esta função configura os GPIOs necessários, inicializa o mutex e define o estado inicial da fechadura como trancada.
 */
void lock_init(void);

/**
 * @brief Destranca a fechadura.
 *
 * @param reason Razão para o destrancamento.
 *
 * Se a fechadura não estiver já destrancada, ativa o atuador, publica o evento via MQTT e inicia o timer de auto-trancamento.
 */
void unlock_door(door_reason_t reason);

/**
 * @brief Tranca a fechadura.
 *
 * @param reason Razão para o trancamento.
 *
 * Desativa o atuador da fechadura e publica o evento via MQTT.
 */
void lock_door(door_reason_t reason);

/**
 * @brief Alterna o estado da fechadura.
 *
 * @param reason Razão para a alternância.
 *
 * Se estiver trancada, destranca; se estiver destrancada, tranca.
 */
void toggle_door(door_reason_t reason);

/**
 * @brief Retorna o estado atual da fechadura.
 *
 * @return Estado atual da fechadura (LOCK_STATE_LOCKED, LOCK_STATE_UNLOCKED ou LOCK_STATE_AUTHENTICATING).
 */
lock_state_t get_lock_state(void);

/**
 * @brief Tarefa para fazer o LED piscar continuamente.
 *
 * @param param Ponteiro para blink_params_t contendo os parâmetros de piscar.
 *
 * Esta função roda em loop infinito, controlando o GPIO do LED conforme os parâmetros fornecidos.
 */
void blink(void *param);

#endif /* LOCK_H */
