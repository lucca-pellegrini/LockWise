/* Configuration Management Header */
#pragma once

#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include <stdint.h>

/**
 * @brief Estrutura que armazena todas as configurações do dispositivo.
 *
 * Esta estrutura contém todas as configurações persistentes armazenadas em NVS (Non-Volatile Storage).
 * Inclui credenciais Wi-Fi, URLs de back-end, configurações MQTT e outros parâmetros operacionais.
 */
typedef struct {
	char wifi_ssid[32]; /**< Nome da rede Wi-Fi para conexão */
	char wifi_password[64]; /**< Senha da rede Wi-Fi */
	char device_id[64]; /**< Identificador único do dispositivo (UUID) */
	char backend_url[256]; /**< URL da API do back-end para streaming de voz */
	char backend_bearer_token[256]; /**< Token de autenticação Bearer para a API do back-end */
	char mqtt_broker_url[256]; /**< URL do broker MQTT para comunicação */
	char mqtt_broker_password[256]; /**< Senha para autenticação no broker MQTT */
	bool mqtt_heartbeat_enable; /**< Habilita/desabilita o heartbeat MQTT periódico */
	int mqtt_heartbeat_interval_sec; /**< Intervalo em segundos entre heartbeats MQTT */
	int audio_record_timeout_sec; /**< Tempo limite para gravação de áudio em segundos */
	int lock_timeout_ms; /**< Tempo para trancamento automático da fechadura em ms */
	int pairing_timeout_sec; /**< Tempo limite para o modo de pareamento em segundos */
	char user_id[256]; /**< ID do usuário pareado */
	bool pairing_mode; /**< Indica se o dispositivo está em modo de pareamento */
	bool voice_detection_enable; /**< Habilita/desabilita detecção de voz */
	int vad_rms_threshold; /**< Limiar RMS para detecção de atividade de voz */
} config_t;

/**
 * @brief Instância global da configuração do dispositivo.
 *
 * Esta variável global armazena todas as configurações atuais do dispositivo.
 * É carregada da NVS na inicialização e pode ser atualizada dinamicamente.
 */
extern config_t config;

/**
 * @brief Carrega a configuração do dispositivo da NVS (Non-Volatile Storage).
 *
 * Esta função lê todas as configurações armazenadas na flash NVS e as carrega na estrutura global config.
 * Se algum valor não estiver presente na NVS, usa valores padrão definidos no menuconfig ou código.
 */
void load_config_from_nvs(void);

/**
 * @brief Atualiza uma configuração específica e a salva na NVS.
 *
 * @param key Chave da configuração a ser atualizada (ex.: "wifi_ssid", "backend_url").
 * @param value Novo valor para a configuração.
 *
 * As chaves válidas incluem: wifi_ssid, wifi_pass, backend_url, backend_bearer, mqtt_broker,
 * mqtt_pass, mqtt_hb_enable, mqtt_hb_interval, audio_timeout, lock_timeout, pairing_timeout,
 * user_id, pairing_mode, voice_detection_enable.
 */
void update_config(const char *key, const char *value);

#endif /* CONFIG_H */
